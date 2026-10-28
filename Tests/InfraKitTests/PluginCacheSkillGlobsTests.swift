import Foundation
import Testing
import DomainKit
@testable import InfraKit

/// OpenCode v2 插件缓存发现：git/npm 插件的 skills 落在
/// `~/.cache/opencode/npm/<pkg>/<ts>/node_modules/<pkg>/skills`（及 dist/skills），
/// 固定子路径覆盖不到——需要 glob 候选（* 匹配单层目录）。
@Suite struct PluginCacheSkillGlobsTests {
    private func makeHome() throws -> URL {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("ak-globs-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        return home
    }

    @Test func openCodeFindsGitPluginSkillCache() async throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let skills = home.appendingPathComponent(
            ".cache/opencode/npm/git-superpowers-abc/1793111846419/node_modules/superpowers/skills",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: skills, withIntermediateDirectories: true)

        let adapter = OpenCodeAdapter(homeDirectory: home)
        let roots = await adapter.skillRoots()
        #expect(roots.contains { $0.path == skills })
        #expect(roots.allSatisfy { $0.owners == ["opencode"] })
    }

    @Test func openCodeFindsNpmPluginDistSkills() async throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let skills = home.appendingPathComponent(
            ".cache/opencode/npm/oh-my-openagent@latest/1790412950595/node_modules/oh-my-openagent/dist/skills",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: skills, withIntermediateDirectories: true)

        let adapter = OpenCodeAdapter(homeDirectory: home)
        let roots = await adapter.skillRoots()
        #expect(roots.contains { $0.path == skills })
    }

    @Test func openCodeKeepsFixedConfigCandidates() async throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let skills = home.appendingPathComponent(".config/opencode/skill", isDirectory: true)
        try FileManager.default.createDirectory(at: skills, withIntermediateDirectories: true)

        let adapter = OpenCodeAdapter(homeDirectory: home)
        let roots = await adapter.skillRoots()
        #expect(roots.contains { $0.path == skills })
    }

    @Test func globResultsAreDeterministicAndDeduped() async throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        for name in ["beta-plugin", "alpha-plugin"] {
            let dir = home.appendingPathComponent(
                ".cache/opencode/npm/git-\(name)/1/node_modules/\(name)/skills", isDirectory: true
            )
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let adapter = OpenCodeAdapter(homeDirectory: home)
        let paths = await adapter.skillRoots().map(\.path.path)
        #expect(paths == paths.sorted())          // 确定性排序
        #expect(Set(paths).count == paths.count)  // 无重复
    }

    @Test func absentCacheYieldsNoGlobRoots() async throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let adapter = OpenCodeAdapter(homeDirectory: home)
        let roots = await adapter.skillRoots()
        #expect(roots.isEmpty)
    }
}
