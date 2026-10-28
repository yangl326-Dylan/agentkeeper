import Foundation
import Testing
import DomainKit
import InfraKit
@testable import AppCore

/// 4.2/4.3：铺设落点更新（每落点先自动快照 → 覆盖 → 部分成功明细与回滚）。
@Suite @MainActor struct DistributionServiceTests {
    private struct Wiring {
        let store: AppStore
        let service: DistributionService
        let snapshotStore: SnapshotStore
        let history: OperationHistory
        let rescanCount: () -> Int
    }

    private func skill(_ name: String, agentID: String, directory: URL, sha: String) -> Skill {
        Skill(
            id: "tag|\(directory.path)",
            name: name,
            directory: directory,
            scope: .agentOnly(agentID: agentID),
            sha256: sha
        )
    }

    private func makeSkill(
        _ home: URL,
        at relative: String,
        body: String,
        name: String,
        agentID: String
    ) throws -> Skill {
        let directory = home.appendingPathComponent(relative, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "---\nname: \(name)\ndescription: 正文\n---\n\(body)\n".write(
            to: directory.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8
        )
        return skill(
            name,
            agentID: agentID,
            directory: directory,
            sha: Fingerprint.sha256OfDirectory(directory)!
        )
    }

    @Test func updateAllLandingPointsSnapshotsThenEqualizes() async throws {
        let home = makeFakeHome(files: ["dummy"])
        defer { cleanup(home) }
        let base = home.appendingPathComponent("ak-base", isDirectory: true)
        let chosen = try makeSkill(home, at: "a/.claude/skills/review", body: "首选版本", name: "review", agentID: "claude-code")
        let otherOne = try makeSkill(home, at: "b/.codex/skills/review", body: "旧版 A", name: "review", agentID: "codex")
        // 同名不同名旁路 skill 不受影响
        let bystander = try makeSkill(home, at: "b/.codex/skills/docs", body: "别的", name: "docs", agentID: "codex")

        let rescanCounter = RescanCounter()
        let snapshotStore = SnapshotStore(baseDirectory: base)
        let history = OperationHistory(directory: base)
        let snapshotService = SnapshotService(snapshots: snapshotStore, history: history, rescan: {})
        let store = AppStore()
        let service = DistributionService(
            store: store,
            snapshotService: snapshotService,
            history: history,
            distributor: SkillDistributor(git: GitInstaller(baseDirectory: base)),
            disabledRoot: base.appendingPathComponent("disabled", isDirectory: true),
            catalogProvider: { [chosen, otherOne, bystander] in
                [chosen, otherOne, bystander]
            },
            rescan: { await rescanCounter.hit() }
        )
        let beforeOtherSha = otherOne.sha256
        let beforeBystanderSha = bystander.sha256

        let summary = await service.updateAllLandingPoints(from: chosen)
        #expect(summary.updated.map(\.agentID) == ["codex"])
        #expect(summary.skippedDisabled.isEmpty)
        #expect(summary.failures.isEmpty)
        #expect(rescanCounter.value == 1)
        // 覆盖后指纹一致
        let afterSha = Fingerprint.sha256OfDirectory(otherOne.directory)
        #expect(afterSha != nil)
        #expect(afterSha == Fingerprint.sha256OfDirectory(chosen.directory))
        // 落点先自动快照（skillID = 落点自身 id）
        #expect(snapshotStore.snapshots(skillID: otherOne.id).count == 1)
        // 旁路不动
        #expect(Fingerprint.sha256OfDirectory(bystander.directory) == beforeBystanderSha)
        // 历史落账
        let recentRecords = history.recent(limit: 5)
        #expect(recentRecords.first?.direction == .updateLandingPoints)
    }

    @Test func disabledLandingPointSkippedAndListed() async throws {
        let home = makeFakeHome(files: ["dummy"])
        defer { cleanup(home) }
        let base = home.appendingPathComponent("ak-base", isDirectory: true)
        let chosen = try makeSkill(home, at: "a/.claude/skills/review", body: "首选版本", name: "review", agentID: "claude-code")
        // 禁用区落点（路径在 disabled 区）
        let disabledDirectory = base.appendingPathComponent("disabled/codex/review", isDirectory: true)
        try FileManager.default.createDirectory(at: disabledDirectory, withIntermediateDirectories: true)
        try "---\nname: review\ndescription: disabled\n---\n禁用版\n".write(
            to: disabledDirectory.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8
        )
        let disabledSkill = skill(
            "review",
            agentID: "codex",
            directory: disabledDirectory,
            sha: Fingerprint.sha256OfDirectory(disabledDirectory)!
        )
        let rescanCounter = RescanCounter()
        let snapshotStore = SnapshotStore(baseDirectory: base)
        let history = OperationHistory(directory: base)
        let snapshotService = SnapshotService(snapshots: snapshotStore, history: history, rescan: {})
        let store = AppStore()
        let service = DistributionService(
            store: store,
            snapshotService: snapshotService,
            history: history,
            distributor: SkillDistributor(git: GitInstaller(baseDirectory: base)),
            disabledRoot: base.appendingPathComponent("disabled", isDirectory: true),
            catalogProvider: { [chosen, disabledSkill] in [chosen, disabledSkill] },
            rescan: { await rescanCounter.hit() }
        )
        let disabledSha = disabledSkill.sha256

        let summary = await service.updateAllLandingPoints(from: chosen)
        #expect(summary.skippedDisabled.map(\.agentID) == ["codex"])
        #expect(summary.updated.isEmpty)
        #expect(Fingerprint.sha256OfDirectory(disabledDirectory) == disabledSha)
        // 禁用落点未被快照
        #expect(snapshotStore.snapshots(skillID: disabledSkill.id).isEmpty)
    }

    @Test func partialFailureRollsBackFailedLandingKeepsOthers() async throws {
        let home = makeFakeHome(files: ["dummy"])
        defer { cleanup(home) }
        let base = home.appendingPathComponent("ak-base", isDirectory: true)
        let chosen = try makeSkill(home, at: "a/.claude/skills/review", body: "首选版本", name: "review", agentID: "claude-code")
        let first = try makeSkill(home, at: "c/.opencode/skills/review", body: "旧版 B", name: "review", agentID: "opencode")
        let second = try makeSkill(home, at: "b/.codex/skills/review", body: "旧版 C", name: "review", agentID: "codex")

        let failingForCodex: SkillDistributor.Copier = { (source: URL, staging: URL) in
            if staging.path.contains(".codex") {
                throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: source.path])
            }
            try SkillDistributor.deepCopyAcrossVolumes(source: source, target: staging)
        }
        let snapshotStore = SnapshotStore(baseDirectory: base)
        let history = OperationHistory(directory: base)
        let snapshotService = SnapshotService(snapshots: snapshotStore, history: history, rescan: {})
        let store = AppStore()
        let service = DistributionService(
            store: store,
            snapshotService: snapshotService,
            history: history,
            distributor: SkillDistributor(
                git: GitInstaller(baseDirectory: base),
                copier: failingForCodex
            ),
            disabledRoot: base.appendingPathComponent("disabled", isDirectory: true),
            catalogProvider: { [chosen, first, second] in [chosen, first, second] },
            rescan: {}
        )
        let beforeSecondSha = second.sha256

        let summary = await service.updateAllLandingPoints(from: chosen)
        // 第一落点成功
        #expect(summary.updated.map(\.agentID) == ["opencode"])
        #expect(Fingerprint.sha256OfDirectory(first.directory) == Fingerprint.sha256OfDirectory(chosen.directory))
        // 第二落点失败但内容原样保留
        #expect(summary.failures.map(\.point.agentID) == ["codex"])
        #expect(Fingerprint.sha256OfDirectory(second.directory) == beforeSecondSha)
        // 无 stage 残留
        for skillEntity in [chosen, first, second] {
            let parent = skillEntity.directory.deletingLastPathComponent()
            let entries = try FileManager.default.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil)
            #expect(entries.filter { $0.lastPathComponent.contains(".ak-") }.isEmpty)
        }
        _ = beforeSecondSha
    }
}

/// 计数器（rescan 合同）。
final class RescanCounter: @unchecked Sendable {
    private var count = 0
    func hit() { count += 1 }
    var value: Int { count }
}
