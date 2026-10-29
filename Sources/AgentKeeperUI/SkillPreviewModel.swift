import Foundation

/// Skill 预览数据异步加载。
/// 根因背景： previously `SkillDetailContent.body` 在主线程同步递归遍历目录 +
/// 同步读 SKILL.md，任何切换/重渲染都卡顿且无加载反馈——现收敛到此后台执行。
@MainActor
enum SkillPreviewModel {
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

    /// 目录内文件相对路径清单（后台递归遍历，确定性排序）。
    static func loadFiles(skillDir: URL) async -> [String] {
        let path = skillDir.path
        return await Task.detached(priority: .userInitiated) {
            let subpaths = (try? FileManager.default.subpathsOfDirectory(atPath: path)) ?? []
            return subpaths.sorted()
        }.value
    }
}
