import Foundation
import DomainKit

/// Claude Code 适配器（具名类型；配置来自 `BuiltInAgents.claudeCode`）。
/// - 检测：`~/.claude/` 存在即 installed
/// - 用户级 skill 根：`~/.claude/skills`
/// - 项目根：`~/.claude.json` 顶层 `projects` 字典
public struct ClaudeCodeAdapter: AgentAdapter {
    private let engine: StandardAgentAdapter

    public init(homeDirectory: URL) {
        self.engine = StandardAgentAdapter(spec: BuiltInAgents.claudeCode, homeDirectory: homeDirectory)
    }

    public var id: AgentID { engine.id }
    public var displayName: String { engine.displayName }
    public func detectInstallation() async -> AgentInstallState { await engine.detectInstallation() }
    public func skillRoots() async -> [SkillRoot] { await engine.skillRoots() }
    public func discoverProjectRoots() async -> [ProjectRoot] { await engine.discoverProjectRoots() }
    public func parseSkill(at directory: URL) async -> ParsedSkill? { await engine.parseSkill(at: directory) }
}
