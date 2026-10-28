import Foundation

// MARK: - 分发来源（skill-distribution spec）

/// 分发操作的来源：本机已识别 skill / 本地目录 / git 仓库。
public enum DistributionSource: Hashable, Codable, Sendable {
    /// 本机某个已识别的 skill（安装到其他 agent，非破坏式复制）。
    case existingSkill(agentID: AgentID, name: String, directoryPath: String)
    /// 用户选择的本地目录（导入；校验 SKILL.md 合法性）。
    case localDirectory(path: String)
    /// git 仓库（clone/本地路径复用后按识别规则发现候选）。
    case gitRepository(url: String)
}

// MARK: - 冲突

/// 安装目标冲突明细：目标已存在且指纹不一致（MUST NOT 覆盖）。
public struct DistributionConflict: Hashable, Codable, Sendable {
    public var targetPath: String
    public var existingSha256: String?
    public var incomingSha256: String

    public init(targetPath: String, existingSha256: String?, incomingSha256: String) {
        self.targetPath = targetPath
        self.existingSha256 = existingSha256
        self.incomingSha256 = incomingSha256
    }
}

// MARK: - git 候选

/// 从 git 仓库发现的 skill 候选（物化目录：临时 clone 或本地只读路径）。
public struct GitSkillCandidate: Hashable, Codable, Sendable, Identifiable {
    /// 仓库来源标识（用户输入的 URL 形式）。
    public var repositoryURL: String
    /// 候选 skill 的物化目录。
    public var directory: URL
    /// 目录名派生的 skill 名称。
    public var name: String
    /// 内容指纹（Fingerprint 规则）。
    public var sha256: String

    /// 列表标识：物化目录唯一指向一个候选。
    public var id: String { directory.path + ":" + name }

    public init(repositoryURL: String, directory: URL, name: String, sha256: String) {
        self.repositoryURL = repositoryURL
        self.directory = directory
        self.name = name
        self.sha256 = sha256
    }
}

// MARK: - 铺设落点

/// 同名 skill 在本机的一个落点（agent + 目录）。
public struct LandingPoint: Hashable, Codable, Sendable {
    public var agentID: AgentID
    public var directory: URL

    public init(agentID: AgentID, directory: URL) {
        self.agentID = agentID
        self.directory = directory
    }
}

// MARK: - 分发错误

/// 分发管线的错误分类（UI 冲突面板按分类呈现，MUST NOT 静默）。
public enum DistributionError: Error, Hashable, Sendable {
    /// 目标已存在且指纹不一致：中止并展示明细，零写入。
    case conflict(DistributionConflict)
    /// 来源不满足 skill 识别规则（缺 SKILL.md / frontmatter 不合法等）。
    case invalidSource(reason: String)
    /// git clone 失败（网络/认证/仓库不存在），detail 透传 git stderr 摘要。
    case cloneFailed(detail: String)
    /// clone 超时。
    case cloneTimeout
    case ioFailure(path: String, underlyingDescription: String)
    /// 目标已存在同名同指纹：报告已铺设，不重复复制。
    case alreadyDistributed(targetPath: String)
}

