import Foundation
import DomainKit
import InfraKit

/// ak CLI：跨 agent skill 管理的命令行伴随（GUI 管人，CLI 管 agent——agent 可自行调用）。
public enum AKCLI {
    // MARK: - 命令解析

    public enum Command: Equatable {
        case list
        case doctor
        case help
        case unknown(String)
    }

    public static func parse(_ args: [String]) -> Command {
        guard let first = args.first else { return .help }
        switch first {
        case "list": return .list
        case "doctor": return .doctor
        case "help", "--help", "-h": return .help
        default: return .unknown(first)
        }
    }

    // MARK: - 运行结果

    public struct RunResult: Equatable, Sendable {
        public var exitCode: Int32
        public var output: String
    }

    // MARK: - 主入口（可注入 home 供测试）

    public static func run(_ args: [String], homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) async -> RunResult {
        switch parse(args) {
        case .help:
            return RunResult(exitCode: 0, output: helpText)
        case .unknown(let name):
            return RunResult(
                exitCode: 2,
                output: "未知命令：\(name)（运行 ak --help 查看用法）\n\n\(helpText)"
            )
        case .list:
            return await runList(homeDirectory: homeDirectory)
        case .doctor:
            return await runDoctor(homeDirectory: homeDirectory)
        }
    }

    // MARK: - list

    static func runList(homeDirectory: URL) async -> RunResult {
        let (skills, agents) = await scan(homeDirectory: homeDirectory)
        var lines: [String] = []
        lines.append(formatSkills(skills))
        lines.append("")
        let installedCount = agents.filter { agent in
            if case .installed = agent.installState { return true }
            return false
        }.count
        lines.append("共 \(skills.count) 个 skill · \(installedCount) 个 agent")
        return RunResult(exitCode: 0, output: lines.joined(separator: "\n"))
    }

    // MARK: - doctor

    static func runDoctor(homeDirectory: URL) async -> RunResult {
        let (skills, agents) = await scan(homeDirectory: homeDirectory)
        let summary = MenuBarSummary.build(
            state: {
                var state = AppState()
                state.agents = agents
                return state
            }(),
            skills: skills
        )
        let entries = summary.agentEntries.map {
            DoctorEntry(id: $0.id, name: $0.name, installed: $0.installed, skillCount: $0.skillCount)
        }
        return RunResult(exitCode: 0, output: formatDoctor(entries))
    }

    struct DoctorEntry {
        let id: String
        let name: String
        let installed: Bool
        let skillCount: Int
    }

    static func formatDoctor(_ entries: [DoctorEntry]) -> String {
        var lines = ["AGENT                STATUS         SKILLS"]
        for entry in entries {
            let status = entry.installed ? "installed" : "not installed"
            lines.append("\(entry.id.padding(toLength: 20, withPad: " ", startingAt: 0))\(status.padding(toLength: 15, withPad: " ", startingAt: 0))\(entry.skillCount)")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - 格式化

    static func formatSkills(_ skills: [Skill]) -> String {
        var lines = ["NAME                SCOPE         AGENTS                       PATH"]
        for skill in skills.sorted(by: { $0.name < $1.name }) {
            let scope: String = {
                switch skill.scope {
                case .global: return "shared"
                case .agentOnly: return "agent-only"
                case .project: return "project"
                case .multiAgent: return "multi-agent"
                }
            }()
            let agents = skill.owners.sorted().joined(separator: ",")
            lines.append(
                [
                    skill.name.padding(toLength: 20, withPad: " ", startingAt: 0),
                    scope.padding(toLength: 14, withPad: " ", startingAt: 0),
                    agents.padding(toLength: 29, withPad: " ", startingAt: 0),
                    skill.directory.path,
                ].joined()
            )
        }
        return lines.joined(separator: "\n")
    }

    static var helpText: String {
        """
        ak — AgentKeeper 命令行：跨 agent 的 skill 管理

        用法: ak <命令>

        命令:
          list     列出全部已发现 skill（名称 / 作用域 / 归属 agent / 路径）
          doctor   检查本机各 agent 的安装状态与 skill 数量
          help     显示本帮助

        更多: https://github.com/yangl326-Dylan/agentkeeper
        """
    }

    // MARK: - 扫描管线（与 GUI AppEnvironment 同构，无 UI 依赖；catalog 同步在 MainActor）

    @MainActor
    private static func scan(homeDirectory: URL) async -> ([Skill], [Agent]) {
        let base = homeDirectory.appendingPathComponent(".agentkeeper", isDirectory: true)
        let store = AppStore()
        let catalogStore = CatalogStore(index: SkillIndex(databaseDirectory: base))
        let runner = InfraScanRunner(homeDirectory: homeDirectory, scopeBaseDirectory: base)
        let scanService = ScanService(store: store, runner: runner)
        await scanService.runScan(projectRoots: [])
        let agents = store.state.agents
        let skills = CatalogBuilder().build(agents: agents)
        await MainActor.run {
            catalogStore.sync(with: skills)
        }
        return (skills, agents)
    }
}
