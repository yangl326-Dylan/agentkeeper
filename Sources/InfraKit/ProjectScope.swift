import Foundation
import DomainKit

// MARK: - 项目级 skill 目录（按 agent）约定

public enum AgentProjectLayout {
    /// 各 agent 在项目根内的 skill 目录候选（相对项目根）。未知约定 → 空数组（体面降级）。
    /// 单一真相：`BuiltInAgents` 的 spec.projectSkillSubpaths。
    public static func projectSkillSubpaths(for agentID: AgentID) -> [String] {
        BuiltInAgents.spec(for: agentID)?.projectSkillSubpaths ?? []
    }

    /// 检测项目级 skill 时需要参与的全部内置 agent（有项目布局者）。
    public static var participatingAgents: [AgentID] {
        BuiltInAgents.all.filter { !$0.projectSkillSubpaths.isEmpty }.map(\.id)
    }
}

// MARK: - 用户添加的项目根（扫描范围管理）

/// 持久化用户显式添加的项目根。文件损坏时回退为空集（磁盘为先真相原则——设置页可重新添加）。
public struct ScanScopeStore {
    public let directory: URL
    private let fileManager = FileManager.default

    public init(directory: URL) throws {
        self.directory = directory
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private var dataFile: URL {
        directory.appendingPathComponent("scan-scope.json")
    }

    /// 用户手动添加的项目根（去重、已持久化）。
    public func userProjectRoots() -> [ProjectRoot] {
        guard let data = try? Data(contentsOf: dataFile) else { return [] }
        guard let entries = try? JSONDecoder().decode(RootList.self, from: data) else { return [] }
        return entries.roots
    }

    public func addProjectRoot(_ root: ProjectRoot) throws {
        var roots = userProjectRoots()
        guard !roots.contains(root) else { return }
        roots.append(root)
        try persist(roots)
    }

    public func removeProjectRoot(_ root: ProjectRoot) throws {
        var roots = userProjectRoots()
        roots.removeAll { $0 == root }
        try persist(roots)
    }

    private func persist(_ roots: [ProjectRoot]) throws {
        let entries = RootList(roots: roots)
        let data = try JSONEncoder().encode(entries)
        try data.write(to: dataFile, options: .atomic)
    }

    private struct RootList: Codable {
        var roots: [ProjectRoot]
    }
}

// MARK: - 项目根内 agent skill 目录扫描

/// 对单个项目根，枚举各 agent 的项目级 skill 目录（存在者才产出 SkillRoot）。
public struct ProjectRootScanner: Sendable {
    /// 参与项目级扫描的 agent 声明（默认内置；调度器会传入 registry 的完整清单）。
    public let specs: [AgentSpec]

    public init(specs: [AgentSpec] = BuiltInAgents.all) {
        self.specs = specs
    }

    public func skillRoots(inProjectRoot root: ProjectRoot) -> [SkillRoot] {
        let fileManager = FileManager.default
        var roots: [SkillRoot] = []
        for spec in specs where !spec.projectSkillSubpaths.isEmpty {
            for subpath in spec.projectSkillSubpaths {
                let candidate = root.path.appendingPathComponent(subpath, isDirectory: true)
                var isDirectory: ObjCBool = false
                if fileManager.fileExists(atPath: candidate.path, isDirectory: &isDirectory), isDirectory.boolValue {
                    roots.append(
                        SkillRoot(
                            path: candidate,
                            owners: [spec.id],
                            level: .project(root)
                        )
                    )
                }
            }
        }
        return roots
    }
}
