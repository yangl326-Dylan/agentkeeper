import Foundation
import DomainKit

/// 一个 agent 的全部声明式知识（单一真相）。
///
/// 新增内置 agent = 在 `BuiltInAgents` 加一个字面量 + 一条测试；
/// 注册表、项目级布局、生命周期枚举、菜单栏图标全部由它派生。
public struct AgentSpec: Sendable, Hashable {
    /// 稳定标识（kebab-case）：用于归属、目录名与 CLI 输出。
    public var id: AgentID
    public var displayName: String
    /// 安装检测候选目录（相对家目录）：任一存在即 installed。
    public var detectionSubpaths: [String]
    /// 用户级 skill 根候选（相对家目录），仅报告实际存在者。
    public var skillRootCandidates: [String]
    /// skill 根 glob 候选（相对家目录，`*` 恰匹配一层）——插件缓存类路径。
    public var skillRootGlobs: [String]
    /// 项目根内的 skill 目录候选（相对项目根）；空 = 不支持项目级。
    public var projectSkillSubpaths: [String]
    /// 项目根发现策略。
    public var projectRootDiscovery: ProjectRootDiscovery
    /// 菜单栏语义图标（SF Symbol）；空串按 terminal 处理。
    public var icon: String

    public init(
        id: AgentID,
        displayName: String,
        detectionSubpaths: [String],
        skillRootCandidates: [String],
        skillRootGlobs: [String] = [],
        projectSkillSubpaths: [String] = [],
        projectRootDiscovery: ProjectRootDiscovery = .none,
        icon: String = "terminal"
    ) {
        self.id = id
        self.displayName = displayName
        self.detectionSubpaths = detectionSubpaths
        self.skillRootCandidates = skillRootCandidates
        self.skillRootGlobs = skillRootGlobs
        self.projectSkillSubpaths = projectSkillSubpaths
        self.projectRootDiscovery = projectRootDiscovery
        self.icon = icon
    }
}

// MARK: - 内置 agent 清单

/// 内置 agent 的唯一声明处。新增 agent 只需在此加一个字面量。
public enum BuiltInAgents {
    /// Claude Code：用户级 `~/.claude/skills`；项目根来自 `~/.claude.json`。
    public static let claudeCode = AgentSpec(
        id: "claude-code",
        displayName: "Claude Code",
        detectionSubpaths: [".claude"],
        skillRootCandidates: [".claude/skills"],
        projectSkillSubpaths: [".claude/skills"],
        projectRootDiscovery: .topLevelJSONProjects(jsonSubpath: ".claude.json"),
        icon: "chevron.left.forwardslash.chevron.right"
    )

    /// OpenCode：`~/.config/opencode`；v2 插件缓存（npm）以 glob 覆盖。
    public static let openCode = AgentSpec(
        id: "opencode",
        displayName: "OpenCode",
        detectionSubpaths: [".config/opencode"],
        skillRootCandidates: [".config/opencode/skill", ".config/opencode/skills"],
        skillRootGlobs: [
            ".cache/opencode/npm/*/*/node_modules/*/skills",
            ".cache/opencode/npm/*/*/node_modules/*/dist/skills",
        ],
        projectSkillSubpaths: [".opencode/skill", ".opencode/skills"],
        icon: "chevron.left.forwardslash.chevron.right"
    )

    /// OpenAI Codex CLI。
    public static let codex = AgentSpec(
        id: "codex",
        displayName: "Codex CLI",
        detectionSubpaths: [".codex"],
        skillRootCandidates: [".codex/skills", ".codex/skill"],
        projectSkillSubpaths: [".codex/skills", ".codex/skill"],
        icon: "chevron.left.forwardslash.chevron.right"
    )

    /// Google Gemini CLI。
    public static let gemini = AgentSpec(
        id: "gemini",
        displayName: "Gemini CLI",
        detectionSubpaths: [".gemini"],
        skillRootCandidates: [".gemini/skills"],
        projectSkillSubpaths: [".gemini/skills"],
        icon: "sparkles"
    )

    /// OpenClaw（原 Clawdbot/Moltbot）：全局 + 工作区双候选。
    public static let openClaw = AgentSpec(
        id: "openclaw",
        displayName: "OpenClaw",
        detectionSubpaths: [".openclaw"],
        skillRootCandidates: [".openclaw/skills", ".openclaw/workspace/skills"],
        icon: "terminal"
    )

    /// pi（minimal harness）。
    public static let pi = AgentSpec(
        id: "pi",
        displayName: "pi",
        detectionSubpaths: [".pi"],
        skillRootCandidates: [".pi/skills", ".pi/agent/skills"],
        icon: "terminal"
    )

    /// oh-my-pi（pi fork，同源结构）。
    public static let ohMyPi = AgentSpec(
        id: "oh-my-pi",
        displayName: "oh-my-pi",
        detectionSubpaths: [".omp", ".config/oh-my-pi"],
        skillRootCandidates: [".omp/skills", ".omp/agent/skills", ".config/oh-my-pi/skills"],
        icon: "terminal"
    )

    /// Agents 共享目录（跨 agent 标准 `~/.agents/skills`）。
    public static let sharedAgents = AgentSpec(
        id: "agents-shared",
        displayName: "Agents 共享目录",
        detectionSubpaths: [".agents"],
        skillRootCandidates: [".agents/skills"],
        icon: "person.2"
    )

    /// Qwen Code（Gemini CLI 系）。
    public static let qwen = AgentSpec(
        id: "qwen",
        displayName: "Qwen Code",
        detectionSubpaths: [".qwen"],
        skillRootCandidates: [".qwen/skills"],
        icon: "sparkles"
    )

    /// Cursor。
    public static let cursor = AgentSpec(
        id: "cursor",
        displayName: "Cursor",
        detectionSubpaths: [".cursor"],
        skillRootCandidates: [".cursor/skills"],
        icon: "cursorarrow.rays"
    )

    /// 全部内置 agent（顺序即注册顺序）。
    public static let all: [AgentSpec] = [
        claudeCode, openCode, codex, gemini, openClaw,
        pi, ohMyPi, sharedAgents, qwen, cursor,
    ]

    public static func spec(for id: AgentID) -> AgentSpec? {
        all.first { $0.id == id }
    }
}
