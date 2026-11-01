import Foundation
import Testing
import DomainKit
@testable import AppCore

/// .timeLimit：本套件曾在 CI（macos-15 runner）发生 MainActor 调度挂起（本机恒过）——
/// 限时把「静默挂死 25min」转化为精确的超时报告并可放行其余测试。
/// .serialized：同套件内消除并发交织变量。
@Suite(.serialized, .timeLimit(.minutes(1))) @MainActor struct OperationServiceTests {
    private var sampleSkill: Skill {
        Skill(
            id: "alpha|claude-code",
            name: "alpha",
            directory: URL(fileURLWithPath: "/tmp/skills/claude/alpha"),
            scope: .agentOnly(agentID: "claude-code"),
            sha256: "sha-a"
        )
    }

    /// 可控执行者：挂起直至测试放行（检查"进行中"状态用）。
    final class GatedPerformer: @unchecked Sendable {
        private let lock = NSLock()
        private var continueBox: [CheckedContinuation<Void, Never>] = []
        var shouldFail = false
        let runs = IntegerBox()

        func gate() async {
            await withCheckedContinuation { continuation in
                lock.lock()
                continueBox.append(continuation)
                lock.unlock()
            }
        }

        func release() {
            lock.lock()
            let boxes = continueBox
            continueBox = []
            lock.unlock()
            for box in boxes { box.resume() }
        }
    }

    @Test func disableOperationShowsRunningThenCompletesAndRescans() async {
        let store = AppStore()
        let report = ScanReport.empty
        let runnerRuns = IntegerBox()
        let scanService = ScanService(
            store: store,
            runner: ConfiguredRunner { _ in
                runnerRuns.increment()
                return report
            }
        )
        let performer = GatedPerformer()
        let service = OperationService(
            store: store,
            scanService: scanService,
            performer: { skill, direction in
                performer.runs.increment()
                await performer.gate()
                if performer.shouldFail { throw OperationError.conflict(detail: "原路径被占用") }
            }
        )

        let task = Task { @MainActor in
            await service.run(skill: sampleSkill, direction: .disable)
        }
        // 进行中：inFlight 已占用，重扫未跑
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(store.state.operation.inFlight?.skillID == "alpha|claude-code")
        #expect(store.state.operation.inFlight?.direction == .disable)
        #expect(runnerRuns.value == 0)
        performer.release()
        await task.value

        // 完成后：inFlight 清空，成功文案清晰，自动触发一次重扫
        #expect(store.state.operation.inFlight == nil)
        #expect(store.state.operation.failureMessage == nil)
        #expect(runnerRuns.value == 1)
        #expect(performer.runs.value == 1)
    }

    @Test func operationFailureRecordedAndNoRescan() async {
        let store = AppStore()
        let runnerRuns = IntegerBox()
        let scanService = ScanService(
            store: store,
            runner: ConfiguredRunner { _ in
                runnerRuns.increment()
                return ScanReport.empty
            }
        )
        let service = OperationService(
            store: store,
            scanService: scanService,
            performer: { _, _ in
                throw OperationError.conflict(detail: "禁用区目标被占用")
            }
        )
        await service.run(skill: sampleSkill, direction: .enable)

        #expect(store.state.operation.inFlight == nil)
        #expect(store.state.operation.failureMessage == "禁用区目标被占用")
        // 失败不重扫（状态保持，UI 冲突面板呈现）
        #expect(runnerRuns.value == 0)
    }
}
