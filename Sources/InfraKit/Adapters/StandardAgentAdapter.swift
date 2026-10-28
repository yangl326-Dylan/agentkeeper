import Foundation
import DomainKit

/// 通用 adapter 引擎：安装检测 + 多候选 skill 根目录枚举 + 标准 SKILL.md 解析。
/// 各 agent 的目录结构约定以"配置"表达；未知结构一律降级，绝不抛错。
public struct StandardAgentAdapter: AgentAdapter {
    public let id: AgentID
    public let displayName: String

    /// 安装检测候选目录（全部相对家目录）。
    private let detectionSubpaths: [String]
    /// skill 根目录候选（相对家目录），仅报告实际存在者。
    private let skillRootCandidates: [String]
    /// skill 根 glob 候选（相对家目录，`*` 恰匹配一层目录）——
    /// 插件缓存类路径（如 OpenCode `npm/<pkg>/<ts>/node_modules/*/skills`）无法用固定子路径表达。
    private let skillRootGlobs: [String]
    /// 项目根发现策略。
    private let projectRootDiscovery: ProjectRootDiscovery

    private let homeDirectory: URL

    public init(
        id: AgentID,
        displayName: String,
        homeDirectory: URL,
        detectionSubpaths: [String],
        skillRootCandidates: [String],
        skillRootGlobs: [String] = [],
        projectRootDiscovery: ProjectRootDiscovery
    ) {
        self.id = id
        self.displayName = displayName
        self.homeDirectory = homeDirectory
        self.detectionSubpaths = detectionSubpaths
        self.skillRootCandidates = skillRootCandidates
        self.skillRootGlobs = skillRootGlobs
        self.projectRootDiscovery = projectRootDiscovery
    }

    // MARK: AgentAdapter

    public func detectInstallation() async -> AgentInstallState {
        let fileManager = FileManager.default
        for subpath in detectionSubpaths {
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
        var paths = skillRootCandidates
            .map { homeDirectory.appendingPathComponent($0, isDirectory: true) }
            .filter { fileManager.fileExists(atPath: $0.path) }
        for pattern in skillRootGlobs {
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
        projectRootDiscovery.discover(homeDirectory: homeDirectory)
    }

    public func parseSkill(at directory: URL) async -> ParsedSkill? {
        SkillParsing.parseDirectory(directory)
    }
}

// MARK: - 项目根发现策略

public enum ProjectRootDiscovery: Sendable {
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

// MARK: - 各 adapter 配置

extension StandardAgentAdapter {
    /// OpenCode：检测 `~/.config/opencode`；skill 目录候选 `skill` / `skills`。
    /// v2 插件缓存（git 与 npm 插件各带 skills/dist-skills）以 glob 覆盖：
    /// `~/.cache/opencode/npm/<pkg>/<ts>/node_modules/<pkg>/(dist/)?skills`。
    public static func openCode(homeDirectory: URL) -> StandardAgentAdapter {
        StandardAgentAdapter(
            id: "opencode",
            displayName: "OpenCode",
            homeDirectory: homeDirectory,
            detectionSubpaths: [".config/opencode"],
            skillRootCandidates: [".config/opencode/skill", ".config/opencode/skills"],
            skillRootGlobs: [
                ".cache/opencode/npm/*/*/node_modules/*/skills",
                ".cache/opencode/npm/*/*/node_modules/*/dist/skills",
            ],
            projectRootDiscovery: .none
        )
    }

    /// OpenAI Codex CLI：检测 `~/.codex`；skill 目录候选 `skills`。
    public static func codex(homeDirectory: URL) -> StandardAgentAdapter {
        StandardAgentAdapter(
            id: "codex",
            displayName: "Codex CLI",
            homeDirectory: homeDirectory,
            detectionSubpaths: [".codex"],
            skillRootCandidates: [".codex/skills", ".codex/skill"],
            projectRootDiscovery: .none
        )
    }

    /// Google Gemini CLI：检测 `~/.gemini`；skill 目录候选 `skills`（扩展体系另计）。
    public static func gemini(homeDirectory: URL) -> StandardAgentAdapter {
        StandardAgentAdapter(
            id: "gemini",
            displayName: "Gemini CLI",
            homeDirectory: homeDirectory,
            detectionSubpaths: [".gemini"],
            skillRootCandidates: [".gemini/skills"],
            projectRootDiscovery: .none
        )
    }

    /// OpenClaw（原 Clawdbot/Moltbot）：检测 `~/.openclaw`；
    /// skill 双候选：全局 `skills` 与工作区 `workspace/skills`。
    public static func openClaw(homeDirectory: URL) -> StandardAgentAdapter {
        StandardAgentAdapter(
            id: "openclaw",
            displayName: "OpenClaw",
            homeDirectory: homeDirectory,
            detectionSubpaths: [".openclaw"],
            skillRootCandidates: [".openclaw/skills", ".openclaw/workspace/skills"],
            projectRootDiscovery: .none
        )
    }

    /// pi（Mario Zechner 的 minimal harness）：检测 `~/.pi`；skill 目录候选 `skills`。
    public static func pi(homeDirectory: URL) -> StandardAgentAdapter {
        StandardAgentAdapter(
            id: "pi",
            displayName: "pi",
            homeDirectory: homeDirectory,
            detectionSubpaths: [".pi"],
            skillRootCandidates: [".pi/skills", ".pi/agent/skills"],
            projectRootDiscovery: .none
        )
    }

    /// Agents 共享目录（跨 agent 标准 `~/.agents/skills`）：检测 `~/.agents`。
    /// 多个 harness（OpenCode/pi/Amp 等）都会读取该共享目录——独立成源，缺它即「搜索不全」。
    public static func sharedAgents(homeDirectory: URL) -> StandardAgentAdapter {
        StandardAgentAdapter(
            id: "agents-shared",
            displayName: "Agents 共享目录",
            homeDirectory: homeDirectory,
            detectionSubpaths: [".agents"],
            skillRootCandidates: [".agents/skills"],
            projectRootDiscovery: .none
        )
    }

    /// Qwen Code（Gemini CLI 系）：检测 `~/.qwen`；skill 目录候选 `skills`。
    public static func qwen(homeDirectory: URL) -> StandardAgentAdapter {
        StandardAgentAdapter(
            id: "qwen",
            displayName: "Qwen Code",
            homeDirectory: homeDirectory,
            detectionSubpaths: [".qwen"],
            skillRootCandidates: [".qwen/skills"],
            projectRootDiscovery: .none
        )
    }

    /// Cursor：检测 `~/.cursor`；skill 目录候选 `skills`。
    public static func cursor(homeDirectory: URL) -> StandardAgentAdapter {
        StandardAgentAdapter(
            id: "cursor",
            displayName: "Cursor",
            homeDirectory: homeDirectory,
            detectionSubpaths: [".cursor"],
            skillRootCandidates: [".cursor/skills"],
            projectRootDiscovery: .none
        )
    }

    /// oh-my-pi（pi 的 fork，同源结构）：检测 `~/.omp` / `~/.config/oh-my-pi`；skill 目录候选 `skills`。
    public static func ohMyPi(homeDirectory: URL) -> StandardAgentAdapter {
        StandardAgentAdapter(
            id: "oh-my-pi",
            displayName: "oh-my-pi",
            homeDirectory: homeDirectory,
            detectionSubpaths: [".omp", ".config/oh-my-pi"],
            skillRootCandidates: [".omp/skills", ".omp/agent/skills", ".config/oh-my-pi/skills"],
            projectRootDiscovery: .none
        )
    }
}
