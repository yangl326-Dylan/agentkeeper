import Foundation
import Testing
import DomainKit
import InfraKit
@testable import AppCore

/// 6.3：CatalogQuery 标签筛选维度（含禁用条目合成，spec：标签 MUST 支持已禁用 skill）。
@Suite struct TagFilterTests {
    private func skill(name: String, path: String, sha256: String) -> Skill {
        Skill(
            id: path,
            name: name,
            directory: URL(fileURLWithPath: path, isDirectory: true),
            scope: .agentOnly(agentID: "claude-code"),
            sha256: sha256
        )
    }

    private func manifestDisabled(idPath: String, home: URL) throws -> String {
        // 真实 manifest 文件：ak/disabled/<agent>/<name>.manifest.json
        let directory = home.appendingPathComponent("ak/disabled/codex", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let manifestURL = directory.appendingPathComponent("review.manifest.json")
        let record = DisabledSkillRecord(
            originalPath: idPath,
            agentID: "codex",
            name: "review",
            sha256: "abc"
        )
        let data = try JSONEncoder().encode(record)
        try data.write(to: manifestURL, options: .atomic)
        return manifestURL.deletingLastPathComponent().path
    }

    @Test func queryWithTagFiltersByIndex() {
        let alpha = skill(name: "alpha", path: "/a/alpha", sha256: "1")
        let beta = skill(name: "beta", path: "/a/beta", sha256: "2")
        let query = CatalogQuery(tag: "写作")
        let filtered = query.apply(
            catalog: [alpha, beta],
            tagsBySkill: ["/a/alpha": ["写作"], "/a/beta": ["实验"]]
        )
        #expect(filtered.map(\.name) == ["alpha"])
    }

    @Test func tagFilterIncludesSyntheticDisabledEntries() throws {
        let home = makeFakeHome(files: ["dummy"])
        defer { cleanup(home) }
        // 该 skill 已禁用：enabled path 失踪，manifest 在 disabled 区
        let enabledPath = "/Users/fake/.codex/skills/review"
        _ = try manifestDisabled(idPath: enabledPath, home: home)
        let store = TagStore(directory: home.appendingPathComponent("ak", isDirectory: true))
        let service = TagService(
            store: store,
            disabledRoot: home.appendingPathComponent("ak/disabled", isDirectory: true)
        )
        store.addDefinition("写作")
        store.assign(tag: "写作", skillID: enabledPath)

        let alive = skill(name: "alpha", path: "/a/alpha", sha256: "1")
        let synthetic = service.disabledTaggedSkills(catalog: [alive])
        #expect(synthetic.count == 1)
        #expect(synthetic[0].name == "review")
        #expect(synthetic[0].status == .disabled)
        #expect(synthetic[0].directory.path == enabledPath)

        // 筛选结果合并（alive 不带该标签 → 不出现；禁用合成条目出现）
        let query = CatalogQuery(tag: "写作")
        let filtered = query.apply(
            catalog: [alive] + synthetic,
            tagsBySkill: [
                "/a/alpha": [],
                enabledPath: ["写作"],
            ]
        )
        #expect(filtered.count == 1)
        #expect(filtered[0].status == .disabled)
    }
}
