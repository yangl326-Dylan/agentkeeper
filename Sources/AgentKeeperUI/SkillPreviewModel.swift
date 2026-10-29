import Foundation

/// Skill 预览数据异步加载。
/// 根因背景： previously `SkillDetailContent.body` 在主线程同步递归遍历目录 +
/// 同步读 SKILL.md，任何切换/重渲染都卡顿且无加载反馈——现收敛到此后台执行。
@MainActor
enum SkillPreviewModel {
    /// Finder 式文件清单条目（相对 skill 目录的路径 + 目录标记）。
    struct FileListEntry: Equatable, Sendable {
        let path: String
        let isDirectory: Bool
    }

    /// SKILL.md 全文（后台读取）；文件缺失给占位文案。
    static func loadMarkdown(skillDir: URL) async -> String {
        let url = skillDir.appendingPathComponent("SKILL.md")
        return await Task.detached(priority: .userInitiated) {
            if let content = try? String(contentsOf: url, encoding: .utf8), !content.isEmpty {
                return content
            }
            return "（SKILL.md 不存在或为空）"
        }.value
    }

    /// 目录内文件清单（后台单次枚举，确定性排序：父目录总在同级子项前）。
    /// 注意 /var 与 /private/var 拼写差异：根与条目路径统一 standardized 后再裁前缀。
    static func loadFiles(skillDir: URL) async -> [FileListEntry] {
        let rootPath = URL(fileURLWithPath: skillDir.path).standardizedFileURL.path
        return await Task.detached(priority: .userInitiated) {
            guard let enumerator = FileManager.default.enumerator(
                at: URL(fileURLWithPath: rootPath, isDirectory: true),
                includingPropertiesForKeys: [.isDirectoryKey],
                options: []
            ) else { return [] }
            var entries: [FileListEntry] = []
            while let anyURL = enumerator.nextObject() as? URL {
                let relative = anyURL.standardizedFileURL.path.dropFirst(rootPath.count + 1)
                guard !relative.isEmpty else { continue }
                let isDirectory = (try? anyURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                entries.append(FileListEntry(path: String(relative), isDirectory: isDirectory))
            }
            return entries.sorted { $0.path < $1.path }
        }.value
    }
}
