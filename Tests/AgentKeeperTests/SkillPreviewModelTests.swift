import Foundation
import Testing
import DomainKit
@testable import AgentKeeperUI

/// Skill 预览异步加载（markdown 内容 + 文件清单）——磁盘 I/O 不得阻塞主线程 body。
@MainActor
@Suite struct SkillPreviewModelTests {
    private func makeSkillDir() throws -> URL {
        let home = makeFakeHomeCore(files: ["d"])
        let dir = home.appendingPathComponent("skills/sample")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func loadsMarkdownContent() async throws {
        let dir = try makeSkillDir()
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }
        try "# 标题\n\n正文".write(
            to: dir.appendingPathComponent("SKILL.md"),
            atomically: true, encoding: .utf8
        )
        let md = await SkillPreviewModel.loadMarkdown(skillDir: dir)
        #expect(md.contains("# 标题"))
    }

    @Test func missingMarkdownYieldsPlaceholder() async throws {
        let dir = try makeSkillDir()
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }
        let md = await SkillPreviewModel.loadMarkdown(skillDir: dir)
        #expect(md.contains("SKILL.md 不存在"))
    }

    @Test func loadsFileListAsync() async throws {
        let dir = try makeSkillDir()
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }
        try "x".write(to: dir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("sub"), withIntermediateDirectories: true)
        try "y".write(to: dir.appendingPathComponent("sub/b.txt"), atomically: true, encoding: .utf8)
        let files = await SkillPreviewModel.loadFiles(skillDir: dir)
        #expect(files.contains("a.txt"))
        #expect(files.contains("sub/b.txt"))
        #expect(files.contains("sub")) // subpathsOfDirectory 含子目录条目
        #expect(files.count == 3)
        #expect(files == files.sorted()) // 确定性排序
    }
}
