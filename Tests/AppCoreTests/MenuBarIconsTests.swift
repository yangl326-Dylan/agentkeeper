import Foundation
import Testing
import DomainKit
@testable import AppCore

/// 菜单栏 agent 行语义图标：已知 ID → 指定图标，未知 ID 回落 terminal。
@Suite struct MenuBarIconsTests {
    @Test func knownAgentIDsMapToSemanticIcons() {
        #expect(MenuBarIcons.icon(for: "claude-code") == "chevron.left.forwardslash.chevron.right")
        #expect(MenuBarIcons.icon(for: "opencode") == "chevron.left.forwardslash.chevron.right")
        #expect(MenuBarIcons.icon(for: "codex") == "chevron.left.forwardslash.chevron.right")
        #expect(MenuBarIcons.icon(for: "cursor") == "cursorarrow.rays")
        #expect(MenuBarIcons.icon(for: "gemini") == "sparkles")
        #expect(MenuBarIcons.icon(for: "qwen") == "sparkles")
        #expect(MenuBarIcons.icon(for: "pi") == "terminal")
        #expect(MenuBarIcons.icon(for: "oh-my-pi") == "terminal")
        #expect(MenuBarIcons.icon(for: "openclaw") == "terminal")
        #expect(MenuBarIcons.icon(for: "agents-shared") == "person.2")
    }

    @Test func unknownIDFallsBackToTerminal() {
        #expect(MenuBarIcons.icon(for: "future-agent") == "terminal")
        #expect(MenuBarIcons.icon(for: "") == "terminal")
    }

    /// 用户自定义 agent 的图标来自 ~/.agentkeeper/agents.json（与内置同一条解析路径）。
    @Test func customAgentIconFromUserConfig() {
        let home = makeFakeHome(files: [], fileContents: [:])
        defer { cleanup(home) }
        let base = home.appendingPathComponent(".agentkeeper", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try? """
        {"agents":[{"id":"windsurf","displayName":"Windsurf","detectionSubpaths":[".windsurf"],"skillRootCandidates":[".windsurf/skills"],"icon":"wind"}]}
        """.write(to: base.appendingPathComponent("agents.json"), atomically: true, encoding: .utf8)

        #expect(MenuBarIcons.icon(for: "windsurf", homeDirectory: home) == "wind")
        // 未配置图标 → terminal
        #expect(MenuBarIcons.icon(for: "not-configured", homeDirectory: home) == "terminal")
    }
}
