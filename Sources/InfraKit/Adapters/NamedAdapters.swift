import Foundation
import DomainKit

// 各 agent 的具名 adapter（测试与客户端用具体类型），
// 内部全部委托 StandardAgentAdapter 引擎 + BuiltInAgents 声明。

/// OpenCode。
public struct OpenCodeAdapter: AgentAdapter {
    private let engine: StandardAgentAdapter
    public init(homeDirectory: URL) {
        self.engine = StandardAgentAdapter(spec: BuiltInAgents.openCode, homeDirectory: homeDirectory)
    }
    public var id: AgentID { engine.id }
    public var displayName: String { engine.displayName }
    public func detectInstallation() async -> AgentInstallState { await engine.detectInstallation() }
    public func skillRoots() async -> [SkillRoot] { await engine.skillRoots() }
    public func discoverProjectRoots() async -> [ProjectRoot] { await engine.discoverProjectRoots() }
    public func parseSkill(at directory: URL) async -> ParsedSkill? { await engine.parseSkill(at: directory) }
}

/// OpenAI Codex CLI。
public struct CodexAdapter: AgentAdapter {
    private let engine: StandardAgentAdapter
    public init(homeDirectory: URL) {
        self.engine = StandardAgentAdapter(spec: BuiltInAgents.codex, homeDirectory: homeDirectory)
    }
    public var id: AgentID { engine.id }
    public var displayName: String { engine.displayName }
    public func detectInstallation() async -> AgentInstallState { await engine.detectInstallation() }
    public func skillRoots() async -> [SkillRoot] { await engine.skillRoots() }
    public func discoverProjectRoots() async -> [ProjectRoot] { await engine.discoverProjectRoots() }
    public func parseSkill(at directory: URL) async -> ParsedSkill? { await engine.parseSkill(at: directory) }
}

/// Google Gemini CLI。
public struct GeminiAdapter: AgentAdapter {
    private let engine: StandardAgentAdapter
    public init(homeDirectory: URL) {
        self.engine = StandardAgentAdapter(spec: BuiltInAgents.gemini, homeDirectory: homeDirectory)
    }
    public var id: AgentID { engine.id }
    public var displayName: String { engine.displayName }
    public func detectInstallation() async -> AgentInstallState { await engine.detectInstallation() }
    public func skillRoots() async -> [SkillRoot] { await engine.skillRoots() }
    public func discoverProjectRoots() async -> [ProjectRoot] { await engine.discoverProjectRoots() }
    public func parseSkill(at directory: URL) async -> ParsedSkill? { await engine.parseSkill(at: directory) }
}

/// OpenClaw（原 Clawdbot/Moltbot）。
public struct OpenClawAdapter: AgentAdapter {
    private let engine: StandardAgentAdapter
    public init(homeDirectory: URL) {
        self.engine = StandardAgentAdapter(spec: BuiltInAgents.openClaw, homeDirectory: homeDirectory)
    }
    public var id: AgentID { engine.id }
    public var displayName: String { engine.displayName }
    public func detectInstallation() async -> AgentInstallState { await engine.detectInstallation() }
    public func skillRoots() async -> [SkillRoot] { await engine.skillRoots() }
    public func discoverProjectRoots() async -> [ProjectRoot] { await engine.discoverProjectRoots() }
    public func parseSkill(at directory: URL) async -> ParsedSkill? { await engine.parseSkill(at: directory) }
}

/// pi（minimal harness）。
public struct PiAdapter: AgentAdapter {
    private let engine: StandardAgentAdapter
    public init(homeDirectory: URL) {
        self.engine = StandardAgentAdapter(spec: BuiltInAgents.pi, homeDirectory: homeDirectory)
    }
    public var id: AgentID { engine.id }
    public var displayName: String { engine.displayName }
    public func detectInstallation() async -> AgentInstallState { await engine.detectInstallation() }
    public func skillRoots() async -> [SkillRoot] { await engine.skillRoots() }
    public func discoverProjectRoots() async -> [ProjectRoot] { await engine.discoverProjectRoots() }
    public func parseSkill(at directory: URL) async -> ParsedSkill? { await engine.parseSkill(at: directory) }
}

/// oh-my-pi（pi fork，同源结构）。
public struct OhMyPiAdapter: AgentAdapter {
    private let engine: StandardAgentAdapter
    public init(homeDirectory: URL) {
        self.engine = StandardAgentAdapter(spec: BuiltInAgents.ohMyPi, homeDirectory: homeDirectory)
    }
    public var id: AgentID { engine.id }
    public var displayName: String { engine.displayName }
    public func detectInstallation() async -> AgentInstallState { await engine.detectInstallation() }
    public func skillRoots() async -> [SkillRoot] { await engine.skillRoots() }
    public func discoverProjectRoots() async -> [ProjectRoot] { await engine.discoverProjectRoots() }
    public func parseSkill(at directory: URL) async -> ParsedSkill? { await engine.parseSkill(at: directory) }
}

/// Agents 共享目录（跨 agent 标准 `~/.agents/skills`）。
public struct SharedAgentsAdapter: AgentAdapter {
    private let engine: StandardAgentAdapter
    public init(homeDirectory: URL) {
        self.engine = StandardAgentAdapter(spec: BuiltInAgents.sharedAgents, homeDirectory: homeDirectory)
    }
    public var id: AgentID { engine.id }
    public var displayName: String { engine.displayName }
    public func detectInstallation() async -> AgentInstallState { await engine.detectInstallation() }
    public func skillRoots() async -> [SkillRoot] { await engine.skillRoots() }
    public func discoverProjectRoots() async -> [ProjectRoot] { await engine.discoverProjectRoots() }
    public func parseSkill(at directory: URL) async -> ParsedSkill? { await engine.parseSkill(at: directory) }
}

/// Qwen Code（Gemini CLI 系）。
public struct QwenAdapter: AgentAdapter {
    private let engine: StandardAgentAdapter
    public init(homeDirectory: URL) {
        self.engine = StandardAgentAdapter(spec: BuiltInAgents.qwen, homeDirectory: homeDirectory)
    }
    public var id: AgentID { engine.id }
    public var displayName: String { engine.displayName }
    public func detectInstallation() async -> AgentInstallState { await engine.detectInstallation() }
    public func skillRoots() async -> [SkillRoot] { await engine.skillRoots() }
    public func discoverProjectRoots() async -> [ProjectRoot] { await engine.discoverProjectRoots() }
    public func parseSkill(at directory: URL) async -> ParsedSkill? { await engine.parseSkill(at: directory) }
}

/// Cursor。
public struct CursorAdapter: AgentAdapter {
    private let engine: StandardAgentAdapter
    public init(homeDirectory: URL) {
        self.engine = StandardAgentAdapter(spec: BuiltInAgents.cursor, homeDirectory: homeDirectory)
    }
    public var id: AgentID { engine.id }
    public var displayName: String { engine.displayName }
    public func detectInstallation() async -> AgentInstallState { await engine.detectInstallation() }
    public func skillRoots() async -> [SkillRoot] { await engine.skillRoots() }
    public func discoverProjectRoots() async -> [ProjectRoot] { await engine.discoverProjectRoots() }
    public func parseSkill(at directory: URL) async -> ParsedSkill? { await engine.parseSkill(at: directory) }
}
