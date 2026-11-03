import Foundation
import Testing
import DomainKit
@testable import AgentKeeperUI

/// Skill 预览异步加载（markdown 内容 + Finder 式文件清单）——磁盘 I/O 不得阻塞主线程 body。
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
        #expect(md?.contains("# 标题") == true)
    }

    /// 缺失 → nil（占位文案由 UI 层按语言渲染，模型不再携带 zh 字符串）。
    @Test func missingMarkdownYieldsNil() async throws {
        let dir = try makeSkillDir()
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }
        let md = await SkillPreviewModel.loadMarkdown(skillDir: dir)
        #expect(md == nil)
    }

    @Test func loadsFileEntriesWithDirectoryFlag() async throws {
        let dir = try makeSkillDir()
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }
        try "x".write(to: dir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("sub"), withIntermediateDirectories: true)
        try "y".write(to: dir.appendingPathComponent("sub/b.txt"), atomically: true, encoding: .utf8)
        let entries = await SkillPreviewModel.loadFiles(skillDir: dir)
        let byPath = Dictionary(uniqueKeysWithValues: entries.map { ($0.path, $0) })
        #expect(byPath["a.txt"]?.isDirectory == false)
        #expect(byPath["sub"]?.isDirectory == true)
        #expect(byPath["sub/b.txt"]?.isDirectory == false)
        #expect(entries.count == 3)
        // 确定性排序：同目录内容相接、父目录在前（Finder 风格展示前置条件）
        let paths = entries.map { entry in entry.path }
        #expect(paths == ["a.txt", "sub", "sub/b.txt"])
    }
}
