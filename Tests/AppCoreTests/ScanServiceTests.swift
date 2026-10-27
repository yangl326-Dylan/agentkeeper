import Foundation
import Testing
import DomainKit
@testable import AppCore

/// 契约先行：ScanRunning 的实现由 AppCore 提供（AppCore 内部组装 InfraKit 调度器）。
@Suite @MainActor struct ScanServiceTests {
    private var sampleReport: ScanReport {
        var report = ScanReport.empty
        report.add(
            agent: Agent(id: "claude-code", name: "Claude Code", installState: .installed(configDirectory: nil)),
            diagnostics: []
        )
        return report
    }

    @Test func runScanDispatchesStartedThenCompleted() async {
        let store = AppStore()
        let report = sampleReport
        var seenRoots: [[ProjectRoot]] = []
        let handler: @Sendable ([ProjectRoot]) async throws -> ScanReport = { roots in
            await MainActor.run {
                seenRoots.append(roots)
            }
            return report
        }
        let service = ScanService(
            store: store,
            runner: ConfiguredRunner(run: handler)
        )
        await service.runScan(projectRoots: [ProjectRoot(path: "/Users/x/code/atlas")])
        #expect(store.state.scan.phase == .complete)
        #expect(store.state.agents.count == 1)
        #expect(store.state.scan.agentCount == 1)
        #expect(seenRoots.count == 1)
        #expect(seenRoots[0].first?.tagName == "atlas")
    }

    @Test func runnerFailureBecomesFailedStateWithoutLosingData() async {
        let store = AppStore()
        var seeded = store.state
        seeded.apply(.scanCompleted(sampleReport))
        let store2 = AppStore(initialState: seeded)
        let service = ScanService(
            store: store2,
            runner: ConfiguredRunner { _ in
                throw SkillAccessError.ioFailure(path: "/tmp/x", underlyingDescription: "disk busy")
            }
        )
        await service.runScan(projectRoots: [])
        #expect(store2.state.scan.phase == .failed)
        // 旧 agent 数据保留（不闪空列表）
        #expect(store2.state.agents.count == 1)
    }

    @Test func scopeChangeTriggersRescan() async {
        let store = AppStore()
        let report = sampleReport
        var runs = 0
        let handler: @Sendable ([ProjectRoot]) async throws -> ScanReport = { _ in
            await MainActor.run { runs += 1 }
            return report
        }
        let service = ScanService(store: store, runner: ConfiguredRunner(run: handler))
        await service.runScan(projectRoots: [])
        await service.rescanAfterScopeChange(added: [ProjectRoot(path: "/Users/x/code/beta")])
        #expect(runs == 2)
    }
}

/// 测试用配置式 runner。
final class ConfiguredRunner: ScanRunning, @unchecked Sendable {
    private let runImpl: @Sendable ([ProjectRoot]) async throws -> ScanReport
    init(run: @escaping @Sendable ([ProjectRoot]) async throws -> ScanReport) {
        self.runImpl = run
    }
    func run(projectRoots: [ProjectRoot]) async throws -> ScanReport {
        try await runImpl(projectRoots)
    }
}
