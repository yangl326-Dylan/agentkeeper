import Foundation
import Testing
import DomainKit
@testable import InfraKit

/// AgentSpec 单源：内置 agent 的全部知识（检测/技能根/项目布局/图标）只在一处声明。
@Suite struct AgentSpecTests {
    @Test func builtInsCoverAllAgentsWithUniqueIDs() {
        let ids = BuiltInAgents.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(Set(ids) == Set([
            "claude-code", "opencode", "codex", "gemini", "openclaw",
            "pi", "oh-my-pi", "agents-shared", "qwen", "cursor", "deepseek",
        ]))
    }

    /// DeepSeek Harness：用户级 + 项目级 .dsh/skills；无项目注册中心（.none）。
    @Test func deepseekHarnessSpec() {
        let spec = BuiltInAgents.spec(for: "deepseek")
        #expect(spec?.displayName == "DeepSeek Harness")
        #expect(spec?.skillRootCandidates == [".dsh/skills"])
        #expect(spec?.projectSkillSubpaths == [".dsh/skills"])
        #expect(spec?.projectRootDiscovery == ProjectRootDiscovery.none)
    }

    /// Claude Code 的项目根来自 ~/.claude.json（唯一使用该策略的内置 agent）。
    @Test func claudeCodeUsesClaudeJSONForProjectDiscovery() {
        let spec = BuiltInAgents.spec(for: "claude-code")
        #expect(spec?.projectRootDiscovery == .topLevelJSONProjects(jsonSubpath: ".claude.json"))
        #expect(spec?.detectionSubpaths == [".claude"])
        #expect(spec?.skillRootCandidates == [".claude/skills"])
        #expect(spec?.projectSkillSubpaths == [".claude/skills"])
    }

    /// OpenCode 插件缓存路径必须保留（npm 缓存无法用固定子路径表达）。
    @Test func openCodeKeepsPluginCacheGlobs() {
        let spec = BuiltInAgents.spec(for: "opencode")
        #expect(spec?.skillRootGlobs == [
            ".cache/opencode/npm/*/*/node_modules/*/skills",
            ".cache/opencode/npm/*/*/node_modules/*/dist/skills",
        ])
    }

    /// 项目级布局由 spec 派生（与旧 AgentProjectLayout 行为一致）。
    @Test func projectLayoutDerivedFromSpecs() {
        #expect(AgentProjectLayout.projectSkillSubpaths(for: "claude-code") == [".claude/skills"])
        #expect(AgentProjectLayout.projectSkillSubpaths(for: "opencode") == [".opencode/skill", ".opencode/skills"])
        #expect(AgentProjectLayout.projectSkillSubpaths(for: "codex") == [".codex/skills", ".codex/skill"])
        #expect(AgentProjectLayout.projectSkillSubpaths(for: "gemini") == [".gemini/skills"])
        #expect(AgentProjectLayout.projectSkillSubpaths(for: "pi").isEmpty)
        #expect(AgentProjectLayout.projectSkillSubpaths(for: "oh-my-pi").isEmpty)
        #expect(AgentProjectLayout.projectSkillSubpaths(for: "openclaw").isEmpty)
        // 未知 agent 体面降级
        #expect(AgentProjectLayout.projectSkillSubpaths(for: "future-agent").isEmpty)

        #expect(AgentProjectLayout.participatingAgents == ["claude-code", "opencode", "codex", "gemini", "deepseek"])
    }

    /// 注册表完全由 specs 派生：10 个内置 adapter，id 与 spec 一致。
    @Test func registryDerivedFromSpecs() {
        let registry = AgentRegistry(
            homeDirectory: URL(fileURLWithPath: "/tmp/ak-nonexistent-home-\(UUID().uuidString)")
        )
        #expect(registry.all.map(\.id) == BuiltInAgents.all.map(\.id))
        #expect(registry.specs.map(\.id) == BuiltInAgents.all.map(\.id))
        #expect(registry.configDiagnostics.isEmpty)
    }
}
