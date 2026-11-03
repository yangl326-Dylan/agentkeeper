import Foundation
import DomainKit
import InfraKit

/// ak CLI：跨 agent skill 管理的命令行伴随（GUI 管人，CLI 管 agent——agent 可自行调用）。
public enum AKCLI {
    // MARK: - 命令解析

    public enum Command: Equatable {
        case list
        case doctor
        case disabled
        case enable(name: String)
        case restore(name: String)
        case purge(name: String)
        case help
        case unknown(String)
    }

    public static func parse(_ args: [String]) -> Command {
        guard let first = args.first else { return .help }
        switch first {
        case "list": return .list
        case "doctor": return .doctor
        case "help", "--help", "-h": return .help
        case "disabled": return .disabled
        case "enable", "restore", "purge":
            guard let name = args.dropFirst().first, !name.isEmpty, args.count == 2 else {
                return .unknown(first)
            }
            switch first {
            case "enable": return .enable(name: name)
            case "restore": return .restore(name: name)
            default: return .purge(name: name)
            }
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
        case .disabled:
            return runDisabled(homeDirectory: homeDirectory)
        case .enable(let name):
            return runEnable(name, homeDirectory: homeDirectory)
        case .restore(let name):
            return runRestore(name, homeDirectory: homeDirectory)
        case .purge(let name):
            return runPurge(name, homeDirectory: homeDirectory)
        }
    }

    // MARK: - 生命周期区（停用 / 回收站）

    /// 生命周期流程入口（每次调用装配；扫描类子命令同法）。
    private static func lifecycle(homeDirectory: URL) -> SkillLifecycle {
        SkillLifecycle(
            baseDirectory: homeDirectory.appendingPathComponent(".agentkeeper", isDirectory: true)
        )
    }

    static func runDisabled(homeDirectory: URL) -> AKCLI.RunResult {
        let lifecycle = Self.lifecycle(homeDirectory: homeDirectory)
        let disabled = (try? lifecycle.disabledEntries()) ?? []
        let trashed = (try? lifecycle.trashEntries()) ?? []
        guard !disabled.isEmpty || !trashed.isEmpty else {
            return RunResult(exitCode: 0, output: "停用区与回收站均为空")
        }
        var lines: [String] = [
            "ZONE                 AGENT         NAME             状态",
            String(repeating: "─", count: 76),
        ]
        for entry in disabled {
            lines.append(zoneLine("停用区", entry, hint: "启用：ak enable \(entry.record.name)"))
        }
        for entry in trashed {
            lines.append(zoneLine("回收站", entry, hint: "恢复：ak restore \(entry.record.name) / 彻底删除：ak purge \(entry.record.name)"))
        }
        lines.append("")
        lines.append("停用 → ak enable <name> · 回收站 → ak restore <name> · 彻底删除 → ak purge <name>")
        return RunResult(exitCode: 0, output: lines.joined(separator: "\n"))
    }

    private static func zoneLine(_ zone: String, _ entry: SkillLifecycle.ZoneEntry, hint: String) -> String {
        "\(zone.padding(toLength: 21, withPad: " ", startingAt: 0))\(entry.record.agentID.padding(toLength: 14, withPad: " ", startingAt: 0))\(entry.record.name.padding(toLength: 17, withPad: " ", startingAt: 0))\(hint)"
    }

    /// 按名在一个区里解析（唯一命中才行动；多副本 → 歧义列出；无 → 未找到）。
    /// 返回 (命中, nil) 或 (nil, 失败结果)。
    private static func resolve(
        _ zoneLabel: String, entries: [SkillLifecycle.ZoneEntry], name: String
    ) -> (entry: SkillLifecycle.ZoneEntry?, failure: AKCLI.RunResult?) {
        let matches = entries.filter { $0.record.name == name }
        if matches.count == 1 { return (matches[0], nil) }
        if matches.isEmpty {
            return (nil, RunResult(exitCode: 1, output: "未找到：\(zoneLabel)中不存在「\(name)」"))
        }
        let listed = matches
            .map { "  · \(zoneLabel) \($0.record.agentID) \($0.record.name)" }
            .joined(separator: "\n")
        return (nil, RunResult(
            exitCode: 1,
            output: "歧义：「\(name)」有多个同名条目，请逐个处理——\n\(listed)"
        ))
    }

    static func runEnable(_ name: String, homeDirectory: URL) -> AKCLI.RunResult {
        let lifecycle = Self.lifecycle(homeDirectory: homeDirectory)
        let entries = (try? lifecycle.disabledEntries()) ?? []
        let (entry, failure) = resolve("停用区", entries: entries, name: name)
        if let failure { return failure }
        guard let entry else { return RunResult(exitCode: 1, output: "未找到") }
        do {
            let record = try lifecycle.enable(agentID: entry.record.agentID, name: name)
            return RunResult(exitCode: 0, output: "已恢复（从停用区）：\(name) → \(record.originalPath)")
        } catch {
            return RunResult(exitCode: 1, output: "恢复失败：\(error)")
        }
    }

    static func runRestore(_ name: String, homeDirectory: URL) -> AKCLI.RunResult {
        let lifecycle = Self.lifecycle(homeDirectory: homeDirectory)
        let entries = (try? lifecycle.trashEntries()) ?? []
        let (entry, failure) = resolve("回收站", entries: entries, name: name)
        if let failure { return failure }
        guard let entry else { return RunResult(exitCode: 1, output: "未找到") }
        do {
            let record = try lifecycle.restoreFromTrash(agentID: entry.record.agentID, name: name)
            return RunResult(exitCode: 0, output: "已从回收站恢复：\(name) → \(record.originalPath)")
        } catch {
            return RunResult(exitCode: 1, output: "恢复失败：\(error)")
        }
    }

    static func runPurge(_ name: String, homeDirectory: URL) -> AKCLI.RunResult {
        let lifecycle = Self.lifecycle(homeDirectory: homeDirectory)
        let entries = (try? lifecycle.trashEntries()) ?? []
        let (entry, failure) = resolve("回收站", entries: entries, name: name)
        if let failure { return failure }
        guard let entry else { return RunResult(exitCode: 1, output: "未找到") }
        do {
            _ = try lifecycle.purgeTrash(agentID: entry.record.agentID, name: name)
            return RunResult(exitCode: 0, output: "已彻底删除：\(name)（内容不可再恢复）")
        } catch {
            return RunResult(exitCode: 1, output: "删除失败：\(error)")
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
          disabled 列出停用区与回收站条目（状态 / 归属 / 恢复方式）
          enable   <name> 从停用区恢复到原路径
          restore  <name> 从回收站恢复到原路径
          purge    <name> 彻底删除回收站条目（不可恢复）
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
