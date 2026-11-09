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
    case global(owners: [AgentID])
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

/// Skill 客观健康问题类型（扫描时收集的事实，非阈值判定）。
public enum SkillIssueKind: Hashable, Codable, Sendable {
    case missingFrontmatter      // 无 frontmatter 块（正文非空）
    case missingName             // 有块缺 name
    case missingDescription      // 有块缺 description（空串视为缺失）
    case emptySkillMd            // SKILL.md 0 字节或 trim 后为空
    case invalidEncoding         // SKILL.md 非 UTF-8
    case brokenSymlink           // 符号链接目标不存在
}

public struct SkillIssue: Hashable, Codable, Sendable {
    public var kind: SkillIssueKind

    public init(kind: SkillIssueKind) {
        self.kind = kind
    }
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
    /// 目录内非隐藏常规文件字节数总和（agent 实际加载口径；与 sha256 同一文件集）。
    public var totalBytes: Int = 0
    /// SKILL.md 字节数。
    public var skillMdBytes: Int = 0
    /// 扫描时收集的客观健康事实（缺 frontmatter 字段、空文件、坏链接等）。
    public var issues: [SkillIssue] = []
    /// 遮蔽我的生效副本 skill id（同名更高优先级副本，同 agent）；nil = 生效或无关系。
    public var shadowedBy: String?
    /// 我遮蔽的同名低优先级副本数（仅生效副本 > 0）。
    public var shadowedCount: Int = 0
    /// 文件形态；legacy 数据默认目录包。
    public var layout: SkillLayout = .directoryPackage

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
        lastModified: Date? = nil,
        totalBytes: Int = 0,
        skillMdBytes: Int = 0,
        issues: [SkillIssue] = [],
        shadowedBy: String? = nil,
        shadowedCount: Int = 0,
        layout: SkillLayout = .directoryPackage
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
        self.totalBytes = totalBytes
        self.skillMdBytes = skillMdBytes
        self.issues = issues
        self.shadowedBy = shadowedBy
        self.shadowedCount = shadowedCount
        self.layout = layout
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, directory, scope, status, sha256
        case frontmatterName, skillDescription, fileCount, lastModified
        case totalBytes, skillMdBytes, issues
        case shadowedBy, shadowedCount
        case layout
    }

    /// 新字段 decodeIfPresent——旧编码输入（无新 key）解码得默认值。
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        directory = try c.decode(URL.self, forKey: .directory)
        scope = try c.decode(SkillScope.self, forKey: .scope)
        status = try c.decode(SkillStatus.self, forKey: .status)
        sha256 = try c.decode(String.self, forKey: .sha256)
        frontmatterName = try c.decodeIfPresent(String.self, forKey: .frontmatterName)
        skillDescription = try c.decodeIfPresent(String.self, forKey: .skillDescription)
        fileCount = try c.decodeIfPresent(Int.self, forKey: .fileCount) ?? 0
        lastModified = try c.decodeIfPresent(Date.self, forKey: .lastModified)
        totalBytes = try c.decodeIfPresent(Int.self, forKey: .totalBytes) ?? 0
        skillMdBytes = try c.decodeIfPresent(Int.self, forKey: .skillMdBytes) ?? 0
        issues = try c.decodeIfPresent([SkillIssue].self, forKey: .issues) ?? []
        shadowedBy = try c.decodeIfPresent(String.self, forKey: .shadowedBy)
        shadowedCount = try c.decodeIfPresent(Int.self, forKey: .shadowedCount) ?? 0
        layout = try c.decodeIfPresent(SkillLayout.self, forKey: .layout) ?? .directoryPackage
    }
}

/// skill 文件形态（DeepSeek Harness 支持目录包与扁平单文件两种）。
public enum SkillLayout: String, Hashable, Codable, Sendable {
    /// `<name>/SKILL.md` 目录包（绝大多数 agent 的约定）。
    case directoryPackage
    /// root 直属 `<name>.md` 单文件（dsh 语义）。
    case flatFile
}

/// 适配器解析出的原始 skill（尚未归一为 Skill 实体）。
public struct ParsedSkill: Hashable, Codable, Sendable {
    public var directory: URL
    public var frontmatterName: String?
    public var frontmatterDescription: String?
    public var files: [URL]
    public var sha256: String
    public var totalBytes: Int = 0
    public var skillMdBytes: Int = 0
    public var issues: [SkillIssue] = []

    public init(
        directory: URL,
        frontmatterName: String? = nil,
        frontmatterDescription: String? = nil,
        files: [URL] = [],
        sha256: String,
        totalBytes: Int = 0,
        skillMdBytes: Int = 0,
        issues: [SkillIssue] = []
    ) {
        self.directory = directory
        self.frontmatterName = frontmatterName
        self.frontmatterDescription = frontmatterDescription
        self.files = files
        self.sha256 = sha256
        self.totalBytes = totalBytes
        self.skillMdBytes = skillMdBytes
        self.issues = issues
    }

    private enum CodingKeys: String, CodingKey {
        case directory, frontmatterName, frontmatterDescription, files, sha256
        case totalBytes, skillMdBytes, issues
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        directory = try c.decode(URL.self, forKey: .directory)
        frontmatterName = try c.decodeIfPresent(String.self, forKey: .frontmatterName)
        frontmatterDescription = try c.decodeIfPresent(String.self, forKey: .frontmatterDescription)
        files = try c.decodeIfPresent([URL].self, forKey: .files) ?? []
        sha256 = try c.decode(String.self, forKey: .sha256)
        totalBytes = try c.decodeIfPresent(Int.self, forKey: .totalBytes) ?? 0
        skillMdBytes = try c.decodeIfPresent(Int.self, forKey: .skillMdBytes) ?? 0
        issues = try c.decodeIfPresent([SkillIssue].self, forKey: .issues) ?? []
    }
}

// MARK: - Skill 实体便利访问

extension Skill {
    /// 项目标签（仅项目级 skill 有）：由项目根路径派生。
    public func projectTag() -> String? {
        scope.projectRoot?.tagName
    }
}

// MARK: - 扫描诊断与报告

public enum ScanDiagnosticKind: Hashable, Codable, Sendable {
    case permissionDenied
    case unrecognizedStructure
    case ioError
}

/// UI 的修复引导语义键。
public enum ScanRemediation: Hashable, Codable, Sendable {
    /// 引导用户到系统设置授权/检查目录权限。
    case grantAccess
    /// 引导用户重试扫描。
    case retry
    /// 无自动修复路径（如结构未知），仅展示。
    case none
}

public struct ScanDiagnostic: Hashable, Codable, Sendable {
    public var path: String
    public var kind: ScanDiagnosticKind
    public var agentID: AgentID?
    public var message: String
    /// UI 修复引导键。
    public var remediation: ScanRemediation

    public init(
        path: String,
        kind: ScanDiagnosticKind,
        agentID: AgentID?,
        message: String,
        remediation: ScanRemediation = .none
    ) {
        self.path = path
        self.kind = kind
        self.agentID = agentID
        self.message = message
        self.remediation = remediation
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
