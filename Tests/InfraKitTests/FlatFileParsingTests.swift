import Foundation
import Testing
import DomainKit
@testable import InfraKit

/// DeepSeek Harness 扁平 skill 文件解析（spec 2026-11-09：root 直属 `<name>.md`）。
@Suite struct FlatFileParsingTests {
    /// 扁平 md：frontmatter name 优先；files=[自身]；指纹=文件内容。
    @Test func parsesFrontmatterAndFingerprint() throws {
        let home = makeFakeHome(
            files: [".dsh/skills/demo.md"],
            fileContents: [".dsh/skills/demo.md": "---\nname: demo\ndescription: d\n---\nBody"]
        )
        defer { cleanup(home) }
        let file = home.appendingPathComponent(".dsh/skills/demo.md")
        let parsed = try #require(SkillParsing.parseFlatFile(at: file))
        #expect(parsed.frontmatterName == "demo")
        #expect(parsed.frontmatterDescription == "d")
        #expect(parsed.files == [file.standardizedFileURL])
        #expect(parsed.skillMdBytes == parsed.totalBytes)
        #expect(parsed.issues.isEmpty)
        #expect(parsed.isFlatFile)
        #expect(!parsed.sha256.isEmpty)
    }

    /// 无 frontmatter 块 → name 缺省（上层用文件名兜底）；单因汇报只报 missingFrontmatter（同 parseDirectory）。
    @Test func bareMarkdownFallsBackToFilename() throws {
        let home = makeFakeHome(files: [".dsh/skills/bare.md"], fileContents: [".dsh/skills/bare.md": "Just text"])
        defer { cleanup(home) }
        let parsed = try #require(SkillParsing.parseFlatFile(at: home.appendingPathComponent(".dsh/skills/bare.md")))
        #expect(parsed.frontmatterName == nil)
        #expect(parsed.issues.map(\.kind) == [.missingFrontmatter])
    }

    /// 有 frontmatter 块但缺 name/description → 逐项上报（与目录包一致）。
    @Test func frontmatterBlockWithMissingFields() throws {
        let home = makeFakeHome(files: [".dsh/skills/half.md"], fileContents: [".dsh/skills/half.md": "---\ndescription: d\n---\nB"])
        defer { cleanup(home) }
        let parsed = try #require(SkillParsing.parseFlatFile(at: home.appendingPathComponent(".dsh/skills/half.md")))
        #expect(parsed.frontmatterName == nil)
        #expect(parsed.frontmatterDescription == "d")
        #expect(parsed.issues.map(\.kind) == [.missingName])
    }

    /// 非 md 返回 nil；空文件报 emptySkillMd。
    @Test func rejectsNonMdAndFlagsEmpty() throws {
        let home = makeFakeHome(
            files: [".dsh/skills/note.txt", ".dsh/skills/empty.md"],
            fileContents: [".dsh/skills/note.txt": "x", ".dsh/skills/empty.md": ""]
        )
        defer { cleanup(home) }
        #expect(SkillParsing.parseFlatFile(at: home.appendingPathComponent(".dsh/skills/note.txt")) == nil)
        let empty = try #require(SkillParsing.parseFlatFile(at: home.appendingPathComponent(".dsh/skills/empty.md")))
        #expect(empty.issues.contains { $0.kind == .emptySkillMd })
    }
}
