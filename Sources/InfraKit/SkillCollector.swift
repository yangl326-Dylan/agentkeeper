import Foundation
import DomainKit

/// 在一个 skill 根目录内递归发现 skill（每层：含 SKILL.md 的目录即 skill；
/// 不是 skill 的目录继续下钻，寻找更深处的 skill）。跳过隐藏目录。
public struct SkillCollector: @unchecked Sendable {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func collect(inRoot root: URL, agentID: AgentID) -> [ParsedSkill] {
        collectRecursive(rootPath: root.path)
            .compactMap { SkillParsing.parseDirectory(at: URL(fileURLWithPath: $0)) }
    }

    /// 返回所有含 SKILL.md 的目录绝对路径（深度优先，跳过隐藏目录）。
    private func collectRecursive(rootPath: String) -> [String] {
        var found: [String] = []
        var workDirs: [String] = [rootPath]
        while !workDirs.isEmpty {
            let current = workDirs.removeLast()
            guard let contents = try? fileManager.contentsOfDirectory(atPath: current) else { continue }
            for entry in contents where !entry.hasPrefix(".") {
                let entryPath = current + "/" + entry
                var isDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: entryPath, isDirectory: &isDirectory), isDirectory.boolValue else {
                    continue
                }
                if fileManager.fileExists(atPath: entryPath + "/SKILL.md") {
                    found.append(entryPath)
                    // skill 目录内部保证不再含嵌套 skill（Claude/OpenCode 约定按目录即一个 skill）
                } else {
                    workDirs.append(entryPath)
                }
            }
        }
        return found.sorted()
    }
}

extension SkillParsing {
    static func parseDirectory(at directory: URL) -> ParsedSkill? {
        parseDirectory(directory)
    }
}
