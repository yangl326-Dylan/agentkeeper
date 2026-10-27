import Foundation
import DomainKit

/// Claude Code 适配器。
/// 检测：`~/.claude/` 存在即 installed。结构版本规则 v1：
/// - 用户级 skill 根：`~/.claude/skills`
/// - 未知子结构（如 plugins 下不识别内容）→ 引发 `.unrecognizedStructure` 类诊断交给扫描器
public struct ClaudeCodeAdapter: AgentAdapter {
    public let id: AgentID = "claude-code"
    public let displayName: String = "Claude Code"

    /// 家目录（可注入 fixture）。
    private let homeDirectory: URL

    public init(homeDirectory: URL) {
        self.homeDirectory = homeDirectory
    }

    public func detectInstallation() async -> AgentInstallState {
        let configDirectory = homeDirectory.appendingPathComponent(".claude", isDirectory: true)
        var isDirectory: ObjCBool = false
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: configDirectory.path, isDirectory: &isDirectory) else {
            return .notInstalled
        }
        guard isDirectory.boolValue else { return .unrecognizedStructure(path: configDirectory.path) }
        return .installed(configDirectory: configDirectory)
    }

    public func skillRoots() async -> [SkillRoot] {
        let fileManager = FileManager.default
        let root = homeDirectory
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("skills", isDirectory: true)
        guard fileManager.fileExists(atPath: root.path) else { return [] }
        return [SkillRoot(path: root, owners: [id], level: .user)]
    }

    public func discoverProjectRoots() async -> [ProjectRoot] {
        // MVP：Claude 的 projects 记录存于 ~/.claude.json（顶层 projects 字典）。
        // 复用通用引擎（含"目录必须真实存在"过滤）。
        ProjectRootDiscovery.topLevelJSONProjects(jsonSubpath: ".claude.json")
            .discover(homeDirectory: homeDirectory)
    }

    public func parseSkill(at directory: URL) async -> ParsedSkill? {
        SkillParsing.parseDirectory(directory)
    }
}
