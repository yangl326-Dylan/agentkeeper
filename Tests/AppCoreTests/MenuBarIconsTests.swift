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
}
