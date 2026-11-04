import Foundation
import DomainKit

/// Agent 适配器注册表。内置 10 个 agent（全部由 `AgentSpec` 派生）+ 用户自定义（agents.json）。
public struct AgentRegistry: Sendable {
    /// 可变注册表：追加用 `append`，新增 agent 无需修改调度器或既有 adapter。
    public private(set) var adapters: [AgentAdapter]
    /// 参与扫描的完整 spec 清单（内置 + 用户自定义）——项目级扫描与图标共用。
    public private(set) var specs: [AgentSpec]
    /// 用户配置文件（agents.json）的加载诊断。
    public private(set) var configDiagnostics: [ScanDiagnostic]

    public init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        let userConfig = UserAgentConfigLoader.load(
            baseDirectory: homeDirectory.appendingPathComponent(".agentkeeper", isDirectory: true)
        )
        let specs = BuiltInAgents.all + userConfig.specs
        self.specs = specs
        self.configDiagnostics = userConfig.diagnostics
        self.adapters = specs.map { StandardAgentAdapter(spec: $0, homeDirectory: homeDirectory) }
    }

    public init(adapters: [AgentAdapter]) {
        self.adapters = adapters
        self.specs = []
        self.configDiagnostics = []
    }

    public var all: [AgentAdapter] { adapters }

    public mutating func append(_ adapter: AgentAdapter) {
        adapters.append(adapter)
    }
}

/// 扫描调度器：并发遍历注册表所有 adapter，聚合 Agent/诊断/共享根。
public struct ScanScheduler: Sendable {
    private let registry: AgentRegistry

    public init(registry: AgentRegistry) {
        self.registry = registry
    }

    /// 执行一次全量扫描。任何 adapter 局部失败都体面降级为诊断，不中断整体。
    /// - Parameter knownProjectRoots: 参与扫描的项目根（adapter 记录 + 用户添加）。
    public func scanAll(rootDirectory: URL? = nil, knownProjectRoots: [ProjectRoot] = []) async -> ScanReport {
        let startedAt = Date()
        var agents: [Agent] = []
        // 用户配置错误必须可见（不静默当作「没有自定义 agent」）
        var diagnostics: [ScanDiagnostic] = registry.configDiagnostics

        await withTaskGroup(of: AgentScanOutcome.self) { group in
            for adapter in registry.all {
                group.addTask {
                    await Self.scan(adapter: adapter)
                }
            }
            for await outcome in group {
                agents.append(outcome.agent)
                diagnostics.append(contentsOf: outcome.diagnostics)
            }
        }

        // 项目根：由通用项目扫描器产出 agent 各自的项目级 skill 根，并入 owner agent
        // 自定义 agent 的项目布局同样来自 spec；无 specs（自定义 registry）时回落内置
        let projectSpecs = registry.specs.isEmpty ? BuiltInAgents.all : registry.specs
        let projectScanner = ProjectRootScanner(specs: projectSpecs)
        var perAgentProjectRoots: [AgentID: [SkillRoot]] = [:]
        for root in knownProjectRoots {
            for skillRoot in projectScanner.skillRoots(inProjectRoot: root) {
                for owner in skillRoot.owners {
                    perAgentProjectRoots[owner, default: []].append(skillRoot)
                }
            }
        }
        for index in agents.indices {
            let candidateRoots = perAgentProjectRoots[agents[index].id] ?? []
            agents[index].skillRoots.append(contentsOf: candidateRoots)
            agents[index].knownProjectRoots = knownProjectRoots
        }

        agents.sort { $0.id < $1.id }
        let sharedRoots = Self.mergeSharedRoots(from: agents)
        return ScanReport(
            agents: agents,
            diagnostics: diagnostics,
            sharedRoots: sharedRoots,
            startedAt: startedAt,
            elapsed: Date().timeIntervalSince(startedAt)
        )
    }

    // MARK: - 单 adapter 扫描

    private struct AgentScanOutcome: Sendable {
        var agent: Agent
        var diagnostics: [ScanDiagnostic]
    }

    private static func scan(adapter: AgentAdapter) async -> AgentScanOutcome {
        let installState = await adapter.detectInstallation()
        let roots = await adapter.skillRoots()
        var diagnostics: [ScanDiagnostic] = []
        let fileManager = FileManager.default

        // 权限检查：根目录不可读 → 权限诊断（绝不错当"无 skill"处理）
        for root in roots {
            if !fileManager.isReadableFile(atPath: root.path.path) {
                diagnostics.append(
                    ScanDiagnostic(
                        path: root.path.path,
                        kind: .permissionDenied,
                        agentID: adapter.id,
                        message: "目录无法读取（权限受限）",
                        remediation: .grantAccess
                    )
                )
            }
        }

        // 项目根发现
        let projectRoots = await adapter.discoverProjectRoots()

        return AgentScanOutcome(
            agent: Agent(
                id: adapter.id,
                name: adapter.displayName,
                installState: installState,
                skillRoots: roots,
                knownProjectRoots: projectRoots
            ),
            diagnostics: diagnostics
        )
    }

    // MARK: - 共享根合并

    static func mergeSharedRoots(from agents: [Agent]) -> [SkillRoot] {
        var byPath: [String: (path: URL, level: SkillRootLevel, owners: Set<AgentID>)] = [:]
        for agent in agents {
            for root in agent.skillRoots {
                let key = root.path.standardizedFileURL.path
                if var existing = byPath[key] {
                    existing.owners.formUnion(root.owners)
                    byPath[key] = existing
                } else {
                    byPath[key] = (root.path, root.level, Set(root.owners))
                }
            }
        }
        return byPath.values
            .map { SkillRoot(path: $0.path, owners: $0.owners.sorted(), level: $0.level) }
            .sorted { $0.path.path < $1.path.path }
    }
}
