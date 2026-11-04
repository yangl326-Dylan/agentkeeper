import Foundation
import DomainKit

/// 通用 adapter 引擎：安装检测 + 多候选 skill 根目录枚举 + 标准 SKILL.md 解析。
/// 各 agent 的目录结构约定以 `AgentSpec` 声明；未知结构一律降级，绝不抛错。
public struct StandardAgentAdapter: AgentAdapter {
    public let id: AgentID
    public let displayName: String

    /// 声明式配置（单一真相）。
    public let spec: AgentSpec

    private let homeDirectory: URL

    public init(spec: AgentSpec, homeDirectory: URL) {
        self.spec = spec
        self.id = spec.id
        self.displayName = spec.displayName
        self.homeDirectory = homeDirectory
    }

    // MARK: AgentAdapter

    public func detectInstallation() async -> AgentInstallState {
        let fileManager = FileManager.default
        for subpath in spec.detectionSubpaths {
            let candidate = homeDirectory.appendingPathComponent(subpath, isDirectory: true)
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: candidate.path, isDirectory: &isDirectory) {
                return isDirectory.boolValue
                    ? .installed(configDirectory: candidate)
                    : .unrecognizedStructure(path: candidate.path)
            }
        }
        return .notInstalled
    }

    public func skillRoots() async -> [SkillRoot] {
        let fileManager = FileManager.default
        var paths = spec.skillRootCandidates
            .map { homeDirectory.appendingPathComponent($0, isDirectory: true) }
            .filter { fileManager.fileExists(atPath: $0.path) }
        for pattern in spec.skillRootGlobs {
            paths.append(contentsOf: Self.expandGlob(pattern, under: homeDirectory, fileManager: fileManager))
        }
        // 排序去重：结果确定性（侧栏/铺设比对依赖稳定顺序）
        // 注意 contentsOfDirectory 在 macOS 上返回 /private/var 前缀——统一归一化后比较
        let unique = Set(paths.map { Self.dropPrivatePrefix($0.path) })
            .sorted()
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
        return unique.map { SkillRoot(path: $0, owners: [id], level: .user) }
    }

    /// /private/var → /var 前缀归一（目录枚举与构造 URL 的拼写差异）。
    static func dropPrivatePrefix(_ path: String) -> String {
        if path.hasPrefix("/private/var/") {
            return String(path.dropFirst("/private".count))
        }
        return path
    }

    /// 展开相对 glob：`*` 恰匹配一层目录组件；路径段逐层枚举，末段须实际存在。
    static func expandGlob(_ pattern: String, under home: URL, fileManager: FileManager) -> [URL] {
        var directories: [URL] = [home]
        for component in pattern.split(separator: "/") {
            let literal = String(component)
            if literal == "*" {
                var next: [URL] = []
                for dir in directories {
                    let entries = (try? fileManager.contentsOfDirectory(
                        at: dir,
                        includingPropertiesForKeys: [.isDirectoryKey],
                        options: [.skipsHiddenFiles]
                    )) ?? []
                    next.append(contentsOf: entries.filter { entry in
                        (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
                    })
                }
                directories = next
            } else {
                directories = directories
                    .map { $0.appendingPathComponent(literal, isDirectory: true) }
                    .filter { fileManager.fileExists(atPath: $0.path) }
            }
            if directories.isEmpty { break }
        }
        return directories
    }

    public func discoverProjectRoots() async -> [ProjectRoot] {
        spec.projectRootDiscovery.discover(homeDirectory: homeDirectory)
    }

    public func parseSkill(at directory: URL) async -> ParsedSkill? {
        SkillParsing.parseDirectory(directory)
    }
}

// MARK: - 项目根发现策略

public enum ProjectRootDiscovery: Hashable, Sendable {
    /// 无项目根记录来源：项目级扫描仅依赖用户手动添加（MVP 铁律）。
    case none
    /// Claude 风格：家目录下 JSON 顶层 `projects` 字典的键为项目绝对路径。
    case topLevelJSONProjects(jsonSubpath: String)

    func discover(homeDirectory: URL) -> [ProjectRoot] {
        let fileManager = FileManager.default
        switch self {
        case .none:
            return []
        case let .topLevelJSONProjects(jsonSubpath):
            let record = homeDirectory.appendingPathComponent(jsonSubpath)
            guard fileManager.fileExists(atPath: record.path),
                  let data = try? Data(contentsOf: record),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let projects = object["projects"] as? [String: Any]
            else { return [] }
            return projects.keys
                .filter { fileManager.fileExists(atPath: $0) }
                .map { ProjectRoot(path: $0) }
        }
    }
}
