import Foundation
import DomainKit

// 各 agent 的具名 adapter（测试与客户端用具体类型），
// 内部全部走 StandardAgentAdapter 引擎。

/// OpenCode。
public struct OpenCodeAdapter: AgentAdapter {
    private let engine: StandardAgentAdapter
    public init(homeDirectory: URL) {
        self.engine = .openCode(homeDirectory: homeDirectory)
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
        self.engine = .codex(homeDirectory: homeDirectory)
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
        self.engine = .gemini(homeDirectory: homeDirectory)
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
        self.engine = .openClaw(homeDirectory: homeDirectory)
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
        self.engine = .pi(homeDirectory: homeDirectory)
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
        self.engine = .ohMyPi(homeDirectory: homeDirectory)
    }
    public var id: AgentID { engine.id }
    public var displayName: String { engine.displayName }
    public func detectInstallation() async -> AgentInstallState { await engine.detectInstallation() }
    public func skillRoots() async -> [SkillRoot] { await engine.skillRoots() }
    public func discoverProjectRoots() async -> [ProjectRoot] { await engine.discoverProjectRoots() }
    public func parseSkill(at directory: URL) async -> ParsedSkill? { await engine.parseSkill(at: directory) }
}
