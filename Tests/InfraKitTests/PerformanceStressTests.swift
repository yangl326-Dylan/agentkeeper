import Foundation
import Testing
import DomainKit
@testable import InfraKit

/// 性能与稳定性压测（7.2）：
/// 扫描 < 2s @ 200 skills；事件风暴下聚合为单次重扫；索引重建可用。
@Suite struct PerformanceStressTests {
    private func makeSkillFarm(count: Int) -> (root: URL, skillDirs: [String]) {
        let home = makeFakeHome(files: [])
        var skillDirs: [String] = []
        for index in 0..<count {
            let dir = home.appendingPathComponent("skills/skill-\(String(format: "%03d", index))", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir.appendingPathComponent("scripts"), withIntermediateDirectories: true)
            try? "---\nname: skill-\(index)\ndescription: perf skill #\(index)\n---\n内容 \(index)".write(to: dir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
            try? "#!/bin/sh\necho \(index)\n".write(to: dir.appendingPathComponent("scripts/run.sh"), atomically: true, encoding: .utf8)
            skillDirs.append(dir.path)
        }
        return (home, skillDirs)
    }

    @Test func scan200SkillsUnderTwoSeconds() {
        let (root, _) = makeSkillFarm(count: 200)
        defer { cleanup(root) }
        // skills 根：一个共享根（200 个 skill 一锅端，最常见的目录布局）
        let start = Date()
        let collector = SkillCollector()
        let _ = collector
        let builder = CatalogBuilder()
        let catalog = builder.build(agents: [
            Agent(
                id: "claude-code",
                name: "Claude",
                installState: .installed(configDirectory: nil),
                skillRoots: [SkillRoot(path: root.appendingPathComponent("skills", isDirectory: true), owners: ["claude-code"], level: .user)]
            ),
        ])
        #expect(catalog.count == 200)
        let elapsed = Date().timeIntervalSince(start)
        #expect(elapsed < 2.0, "200-skill 全量解析+编目应在 2s 内，实际 \(elapsed)s")
    }

    @Test func indexUpsertAndRebuildAt200Scale() {
        let (root, _) = makeSkillFarm(count: 200)
        defer { cleanup(root) }
        let collector = SkillCollector()
        let skills = collector.collect(inRoot: root.appendingPathComponent("skills", isDirectory: true), agentID: "claude-code")
            .compactMap { parsed -> Skill? in
                Skill(
                    id: parsed.directory.lastPathComponent,
                    name: parsed.frontmatterName ?? "",
                    directory: parsed.directory,
                    scope: .agentOnly(agentID: "claude-code"),
                    sha256: parsed.sha256
                )
            }

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ak-perf-\(UUID().uuidString)", isDirectory: true)
        let index = SkillIndex(databaseDirectory: dir)
        let upsertStart = Date()
        index.upsert(skills)
        #expect(index.all().count == 200)
        let upsertElapsed = Date().timeIntervalSince(upsertStart)
        #expect(upsertElapsed < 2.0, "200 行索引 upsert 应在 2s 内，实际 \(upsertElapsed)s")

        let rebuildStart = Date()
        index.rebuild()
        #expect(index.integrity())
        let rebuildElapsed = Date().timeIntervalSince(rebuildStart)
        #expect(rebuildElapsed < 2.0, "索引重建应在 2s 内，实际 \(rebuildElapsed)s")
    }
}
