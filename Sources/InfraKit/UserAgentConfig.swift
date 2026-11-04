import Foundation
import DomainKit

/// 用户自定义 agent 的加载结果：合法 spec + 诊断（非法条目绝不静默丢弃）。
public struct UserAgentConfigLoadResult: Sendable {
    public var specs: [AgentSpec]
    public var diagnostics: [ScanDiagnostic]

    public init(specs: [AgentSpec] = [], diagnostics: [ScanDiagnostic] = []) {
        self.specs = specs
        self.diagnostics = diagnostics
    }
}

/// `~/.agentkeeper/agents.json` 加载器。
///
/// 设计原则（宁严勿松）：
/// - 内置 id 优先，禁止覆盖（防劫持）
/// - 路径必须相对家目录（禁止绝对路径 / `~` / `.` / `..`）
/// - 任何非法条目只影响自身，绝不阻塞扫描
public enum UserAgentConfigLoader {
    public static let fileName = "agents.json"

    public static func load(baseDirectory: URL) -> UserAgentConfigLoadResult {
        let url = baseDirectory.appendingPathComponent(fileName, isDirectory: false)
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else {
            return UserAgentConfigLoadResult()
        }
        guard let data = try? Data(contentsOf: url) else {
            return UserAgentConfigLoadResult(diagnostics: [
                diagnostic(url, nil, "无法读取 agents.json（权限或 IO 错误）"),
            ])
        }

        let config: ConfigFile
        do {
            config = try JSONDecoder().decode(ConfigFile.self, from: data)
        } catch {
            return UserAgentConfigLoadResult(diagnostics: [
                diagnostic(url, nil, "agents.json 解析失败：\(error.localizedDescription)"),
            ])
        }

        let builtInIDs = Set(BuiltInAgents.all.map(\.id))
        var specs: [AgentSpec] = []
        var diagnostics: [ScanDiagnostic] = []
        var seen = Set<AgentID>()

        for entry in config.agents ?? [] {
            let id = entry.id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isValidID(id) else {
                diagnostics.append(diagnostic(url, nil, "忽略条目：id 非法（须为小写 kebab-case）：\(entry.id)"))
                continue
            }
            guard !builtInIDs.contains(id) else {
                diagnostics.append(diagnostic(url, id, "忽略条目：id 与内置 agent 冲突（内置优先）：\(id)"))
                continue
            }
            guard seen.insert(id).inserted else {
                diagnostics.append(diagnostic(url, id, "忽略条目：id 重复（先出现者生效）：\(id)"))
                continue
            }
            guard !entry.detectionSubpaths.isEmpty else {
                diagnostics.append(diagnostic(url, id, "忽略条目：detectionSubpaths 不能为空：\(id)"))
                continue
            }
            let paths = entry.detectionSubpaths
                + entry.skillRootCandidates
                + (entry.skillRootGlobs ?? [])
                + (entry.projectSkillSubpaths ?? [])
            guard paths.allSatisfy(isSafeRelativePath) else {
                diagnostics.append(diagnostic(
                    url, id,
                    "忽略条目：路径必须是家目录下的相对路径（禁止绝对路径、~、. 与 ..）：\(id)"
                ))
                continue
            }
            if let discovery = entry.projectRootDiscovery, discovery != "none" {
                diagnostics.append(diagnostic(url, id, "忽略条目：projectRootDiscovery 目前仅支持 \"none\"：\(id)"))
                continue
            }

            let displayName = entry.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let icon = entry.icon?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            specs.append(AgentSpec(
                id: id,
                displayName: displayName.isEmpty ? id : displayName,
                detectionSubpaths: entry.detectionSubpaths,
                skillRootCandidates: entry.skillRootCandidates,
                skillRootGlobs: entry.skillRootGlobs ?? [],
                projectSkillSubpaths: entry.projectSkillSubpaths ?? [],
                projectRootDiscovery: .none,
                icon: icon.isEmpty ? "terminal" : icon
            ))
        }

        return UserAgentConfigLoadResult(specs: specs, diagnostics: diagnostics)
    }

    // MARK: - 校验

    static func isValidID(_ id: String) -> Bool {
        id.range(of: "^[a-z0-9][a-z0-9-]*$", options: .regularExpression) != nil
    }

    static func isSafeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.hasPrefix("~") else { return false }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        return components.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }

    private static func diagnostic(_ url: URL, _ agentID: AgentID?, _ message: String) -> ScanDiagnostic {
        ScanDiagnostic(
            path: url.path,
            kind: .unrecognizedStructure,
            agentID: agentID,
            message: message,
            remediation: .none
        )
    }

    // MARK: - JSON 结构

    private struct ConfigFile: Decodable {
        var agents: [Entry]?
    }

    private struct Entry: Decodable {
        var id: String
        var displayName: String?
        var detectionSubpaths: [String]
        var skillRootCandidates: [String]
        var skillRootGlobs: [String]?
        var projectSkillSubpaths: [String]?
        var projectRootDiscovery: String?
        var icon: String?
    }
}
