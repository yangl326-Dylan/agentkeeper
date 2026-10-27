import Foundation

// MARK: - AgentAdapter

/// 一个 agent 的适配器：声明如何检测安装、枚举 skill 根目录、发现项目根、解析 skill。
/// 新增 agent 只需新增一个符合该协议的类型并注册进 AgentRegistry。
public protocol AgentAdapter: Sendable {
    /// 稳定标识，如 "claude-code"。
    var id: AgentID { get }
    /// 展示名。
    var displayName: String { get }

    /// 检测安装状态。必须可对不存在目录/无权限返回降级结果而非抛错。
    func detectInstallation() async -> AgentInstallState

    /// 枚举用户级（和/或共享）skill 根目录。
    func skillRoots() async -> [SkillRoot]

    /// 从 agent 自身配置/记录中发现已知项目根。
    /// MVP 铁律：绝不递归扫描任意目录；无记录来源时返回空数组。
    func discoverProjectRoots() async -> [ProjectRoot]

    /// 解析位于某个skill根目录内的候选目录，不合规则返回 nil（忽略，不报错）。
    func parseSkill(at directory: URL) async -> ParsedSkill?
}

// MARK: - 扫描资源访问异常

public enum SkillAccessError: Error, Hashable, Sendable {
    case permissionDenied(path: String)
    case ioFailure(path: String, underlyingDescription: String)
}

// MARK: - 文件监控抽象

/// 文件系统事件（聚合后）。
public struct FileChangeEvent: Hashable, Sendable {
    public var rootPath: String
    public var occurredAt: Date

    public init(rootPath: String, occurredAt: Date = Date()) {
        self.rootPath = rootPath
        self.occurredAt = occurredAt
    }
}

/// 目录监听抽象。实现：FSEvents；测试：FakeMonitor。
public protocol FileMonitoring: Sendable, Actor {
    /// 开始监听一组根目录；事件按 rootPath 聚合推送。
    func start(watchingRoots: [URL]) async
    func stopAll() async
}
