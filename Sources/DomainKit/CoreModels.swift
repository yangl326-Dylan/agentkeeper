import Foundation

// MARK: - 基础标识

/// Agent 标识（kebab-case，如 "claude-code"）。
public typealias AgentID = String

// MARK: - 项目根与项目标签

/// 一个已知的项目根目录。项目标签（tagName）由路径末段派生，零维护。
public struct ProjectRoot: Hashable, Codable, Sendable {
    /// 规范化后的路径（无尾部斜杠）。
    public var path: URL
    /// `/a/b/name/` → `name`
    public var tagName: String {
        let string = path.path
        var trimmed = string
        if trimmed.count > 1 && trimmed.hasSuffix("/") { trimmed.removeLast() }
        return (trimmed as NSString).lastPathComponent
    }

    /// 用字符串初始化并规范化路径。
    public init(path: String) {
        var trimmed = path
        if trimmed.count > 1 && trimmed.hasSuffix("/") { trimmed.removeLast() }
        self.path = URL(fileURLWithPath: trimmed, isDirectory: true)
    }

    public init(path: URL) {
        self.path = path
    }
}

// MARK: - Skill 作用域

/// Skill 的作用域，判定规则确定性且可解释：
/// - 项目根内 → `.project`（自动携带项目标签）
/// - 被多个 agent 引用的目录 → `.global`
/// - 单一 agent 私有目录 → `.agentOnly`
/// - 同名同指纹铺设在多个 agent 目录 → `.multiAgent`
public enum SkillScope: Hashable, Codable, Sendable {
    case global
    case agentOnly(agentID: AgentID)
    case project(agentID: AgentID, root: ProjectRoot)
    case multiAgent([AgentID])

    /// 项目级作用域对应的项目根；其它为 nil。
    public var projectRoot: ProjectRoot? {
        if case let .project(_, root) = self { return root }
        return nil
    }

    /// 项目级作用域对应的所属 agent；其它为 nil。
    public var agentIDForOwner: AgentID? {
        switch self {
        case let .project(agentID, _): agentID
        case let .agentOnly(agentID): agentID
        case .global, .multiAgent: nil
        }
    }
}

// MARK: - Agent 安装状态/根目录

public enum AgentInstallState: Hashable, Codable, Sendable {
    case installed(configDirectory: URL?)
    case notInstalled
    /// 目录存在但内部结构无法匹配已知版本规则。
    case unrecognizedStructure(path: String)
}

public enum SkillRootLevel: Hashable, Codable, Sendable {
    case user
    case project(ProjectRoot)
}

public struct SkillRoot: Hashable, Codable, Sendable {
    public var path: URL
    /// 读取该根目录的所有 agent（≥2 即共享目录，判定全局作用域的依据）。
    public var owners: [AgentID]
    public var level: SkillRootLevel

    public init(path: URL, owners: [AgentID], level: SkillRootLevel) {
        self.path = path
        self.owners = owners
        self.level = level
    }
}

// MARK: - Agent

public struct Agent: Hashable, Codable, Sendable, Identifiable {
    public var id: AgentID
    public var name: String
    public var installState: AgentInstallState
    public var skillRoots: [SkillRoot]
    /// 该 agent 已知的可扫描项目根（MVP：项目级扫描只使用显式确认过的项目根）。
    public var knownProjectRoots: [ProjectRoot]

    public init(
        id: AgentID,
        name: String,
        installState: AgentInstallState,
        skillRoots: [SkillRoot] = [],
        knownProjectRoots: [ProjectRoot] = []
    ) {
        self.id = id
        self.name = name
        self.installState = installState
        self.skillRoots = skillRoots
        self.knownProjectRoots = knownProjectRoots
    }
}

// MARK: - Skill 状态与实体

public enum SkillStatus: Hashable, Codable, Sendable {
    case enabled
    case disabled
}

public struct Skill: Hashable, Codable, Sendable, Identifiable {
    /// 稳定标识：作用域内目录路径派生。
    public var id: String
    public var name: String
    public var directory: URL
    public var scope: SkillScope
    public var status: SkillStatus
    /// 内容 SHA256（覆盖 SKILL.md 与随附文件）。
    public var sha256: String
    public var frontmatterName: String?
    public var skillDescription: String?
    public var fileCount: Int
    public var lastModified: Date?

    public init(
        id: String,
        name: String,
        directory: URL,
        scope: SkillScope,
        status: SkillStatus = .enabled,
        sha256: String,
        frontmatterName: String? = nil,
        skillDescription: String? = nil,
        fileCount: Int = 0,
        lastModified: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.directory = directory
        self.scope = scope
        self.status = status
        self.sha256 = sha256
        self.frontmatterName = frontmatterName
        self.skillDescription = skillDescription
        self.fileCount = fileCount
        self.lastModified = lastModified
    }
}

/// 适配器解析出的原始 skill（尚未归一为 Skill 实体）。
public struct ParsedSkill: Hashable, Codable, Sendable {
    public var directory: URL
    public var frontmatterName: String?
    public var frontmatterDescription: String?
    public var files: [URL]
    public var sha256: String

    public init(
        directory: URL,
        frontmatterName: String? = nil,
        frontmatterDescription: String? = nil,
        files: [URL] = [],
        sha256: String
    ) {
        self.directory = directory
        self.frontmatterName = frontmatterName
        self.frontmatterDescription = frontmatterDescription
        self.files = files
        self.sha256 = sha256
    }
}

// MARK: - 扫描诊断与报告

public enum ScanDiagnosticKind: Hashable, Codable, Sendable {
    case permissionDenied
    case unrecognizedStructure
    case ioError
}

public struct ScanDiagnostic: Hashable, Codable, Sendable {
    public var path: String
    public var kind: ScanDiagnosticKind
    public var agentID: AgentID?
    public var message: String

    public init(path: String, kind: ScanDiagnosticKind, agentID: AgentID?, message: String) {
        self.path = path
        self.kind = kind
        self.agentID = agentID
        self.message = message
    }
}

/// 一次全量扫描的聚合结果。
public struct ScanReport: Hashable, Codable, Sendable {
    public var agents: [Agent]
    public var diagnostics: [ScanDiagnostic]
    /// 跨 agent 的共享/全局根目录视图（同一路径多方引用 → owners 并集）。
    public var sharedRoots: [SkillRoot]
    public var startedAt: Date
    public var elapsed: TimeInterval

    public static let empty = ScanReport(agents: [], diagnostics: [], sharedRoots: [], startedAt: Date(), elapsed: 0)

    public init(
        agents: [Agent],
        diagnostics: [ScanDiagnostic],
        sharedRoots: [SkillRoot] = [],
        startedAt: Date,
        elapsed: TimeInterval
    ) {
        self.agents = agents
        self.diagnostics = diagnostics
        self.sharedRoots = sharedRoots
        self.startedAt = startedAt
        self.elapsed = elapsed
    }

    public mutating func add(agent: Agent, diagnostics: [ScanDiagnostic]) {
        if let index = agents.firstIndex(where: { $0.id == agent.id }) {
            agents[index] = agent
        } else {
            agents.append(agent)
        }
        self.diagnostics.append(contentsOf: diagnostics)
    }
}
