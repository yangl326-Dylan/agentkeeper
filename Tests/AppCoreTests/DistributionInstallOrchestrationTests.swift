import Foundation
import Testing
import DomainKit
import InfraKit
@testable import AppCore

/// 6.1/6.2：分发安装接入操作状态机（成功自动重扫/失败不重扫）与串行化。
@Suite @MainActor struct DistributionInstallOrchestrationTests {
    private func makeSkillBody(name: String, body: String) -> String {
        "---\nname: \(name)\ndescription: 正文\n---\n\(body)\n"
    }

    private func makeFixture() -> (home: URL, base: URL) {
        let home = makeFakeHome(files: ["dummy"])
        return (home, home.appendingPathComponent("ak-base", isDirectory: true))
    }

    @Test func successfulInstallCompletesAndRescans() async throws {
        let fixture = makeFixture()
        defer { cleanup(fixture.home) }
        let (home, base) = fixture
        let source = home.appendingPathComponent("source/review", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try makeSkillBody(name: "review", body: "v1").write(
            to: source.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8
        )
        let targetRoot = home.appendingPathComponent("agent/skills", isDirectory: true)

        let rescanCounter = RescanCounter()
        let history = OperationHistory(directory: base)
        let snapshotService = SnapshotService(snapshots: SnapshotStore(baseDirectory: base), history: history, rescan: {})
        let store = AppStore()
        let service = DistributionService(
            store: store,
            snapshotService: snapshotService,
            history: history,
            distributor: SkillDistributor(git: GitInstaller(baseDirectory: base)),
            disabledRoot: base.appendingPathComponent("disabled", isDirectory: true),
            rescan: { await rescanCounter.hit() }
        )

        #expect(store.state.operation.inFlight == nil)
        await service.install(
            source: .localDirectory(path: source.path),
            targetSkillRoot: targetRoot,
            displaySkillID: "install|review",
            displayName: "review"
        )
        #expect(rescanCounter.value == 1) // 成功自动重扫
        #expect(store.state.operation.inFlight == nil)
        #expect(store.state.operation.failureMessage == nil)
        #expect(history.recent(limit: 5).first?.direction == .distribute)
        #expect(FileManager.default.fileExists(atPath: targetRoot.appendingPathComponent("review", isDirectory: true).path))
    }

    @Test func failedInstallDoesNotRescan() async throws {
        let fixture = makeFixture()
        defer { cleanup(fixture.home) }
        let (home, base) = fixture
        let targetRoot = home.appendingPathComponent("agent/skills", isDirectory: true)
        // 来源不存在 → 失败
        let rescanCounter = RescanCounter()
        let history = OperationHistory(directory: base)
        let snapshotService = SnapshotService(snapshots: SnapshotStore(baseDirectory: base), history: history, rescan: {})
        let store = AppStore()
        let service = DistributionService(
            store: store,
            snapshotService: snapshotService,
            history: history,
            distributor: SkillDistributor(git: GitInstaller(baseDirectory: base)),
            disabledRoot: base.appendingPathComponent("disabled", isDirectory: true),
            rescan: { await rescanCounter.hit() }
        )
        await service.install(
            source: .localDirectory(path: home.appendingPathComponent("nope").path),
            targetSkillRoot: targetRoot,
            displaySkillID: "install|missing",
            displayName: "missing"
        )
        #expect(rescanCounter.value == 0) // 失败不重扫
        #expect(store.state.operation.failureMessage != nil)
        #expect(store.state.operation.inFlight == nil)
        let failureRecord = history.recent(limit: 5).first
        #expect(failureRecord?.direction == .distribute)
        guard case .failure = failureRecord?.result else {
            Issue.record("expected failure record")
            return
        }
    }

    @Test func concurrentInstallsAreSerialized() async throws {
        let fixture = makeFixture()
        defer { cleanup(fixture.home) }
        let (home, base) = fixture
        let targetRoot = home.appendingPathComponent("agent/skills", isDirectory: true)
        let alpha = home.appendingPathComponent("src/alpha", isDirectory: true)
        let beta = home.appendingPathComponent("src/beta", isDirectory: true)
        for (name, directory) in [("alpha", alpha), ("beta", beta)] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try makeSkillBody(name: name, body: "正文").write(
                to: directory.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8
            )
        }

        final class CopierLog: @unchecked Sendable {
            private let lock = NSLock()
            private var events: [String] = []
            func record(_ event: String) {
                lock.lock(); defer { lock.unlock() }
                events.append(event)
            }
            func snapshot() -> [String] {
                lock.lock(); defer { lock.unlock() }
                return events
            }
        }
        let copier = CopierLog()
        let slowCopier: SkillDistributor.Copier = { (source: URL, staging: URL) in
            let label = staging.path.contains("alpha") ? "alpha" : "beta"
            copier.record("start-\(label)")
            do {
                // 同步阻塞等待以保持 Copier 为同步签名
                try Task.checkCancellation()
                let deadline = Date().addingTimeInterval(1.0)
                while Date() < deadline { }
            } catch { /* 忽略 */ }
            copier.record("finish-\(label)")
            try SkillDistributor.deepCopyAcrossVolumes(source: source, target: staging)
        }
        let history = OperationHistory(directory: base)
        let snapshotService = SnapshotService(snapshots: SnapshotStore(baseDirectory: base), history: history, rescan: {})
        let store = AppStore()
        let service = DistributionService(
            store: store,
            snapshotService: snapshotService,
            history: history,
            distributor: SkillDistributor(
                git: GitInstaller(baseDirectory: base),
                copier: slowCopier
            ),
            disabledRoot: base.appendingPathComponent("disabled", isDirectory: true),
            rescan: {}
        )

        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await service.install(
                    source: .localDirectory(path: alpha.path),
                    targetSkillRoot: targetRoot,
                    displaySkillID: "alpha",
                    displayName: "alpha"
                )
            }
            group.addTask {
                await service.install(
                    source: .localDirectory(path: beta.path),
                    targetSkillRoot: targetRoot,
                    displaySkillID: "beta",
                    displayName: "beta"
                )
            }
        }

        let events = copier.snapshot()
        #expect(events.count == 4)
        // 无交错：start-X … finish-X 中不得插入 start-Y
        if let startIndex = events.firstIndex(where: { $0.hasPrefix("start-") }) {
            let label = events[startIndex].dropFirst("start-".count)
            let finishIndex = events.firstIndex(where: { $0 == "finish-\(label)" })
            let overlapping = events.dropFirst(startIndex).prefix(while: { $0 != "finish-\(label)" })
                .contains { $0.hasPrefix("start-") && $0 != "start-\(label)" }
            #expect(finishIndex != nil)
            #expect(!overlapping)
        }
        // 两个目标都存在
        #expect(FileManager.default.fileExists(atPath: targetRoot.appendingPathComponent("alpha").path))
        #expect(FileManager.default.fileExists(atPath: targetRoot.appendingPathComponent("beta").path))
    }
}
