import Foundation
import Testing
import DomainKit
@testable import InfraKit

@Suite struct FrontmatterDetailedTests {
    @Test func noBlockReportsHasFrontmatterFalse() {
        let d = FrontmatterParser.parseDetailed(markdown: "# Hello\n\nbody")
        #expect(d.hasFrontmatter == false)
        #expect(d.name == nil)
        #expect(d.description == nil)
    }

    @Test func blockWithBothKeysReportsTrue() {
        let md = "---\nname: demo\ndescription: does things\n---\n\nbody"
        let d = FrontmatterParser.parseDetailed(markdown: md)
        #expect(d.hasFrontmatter == true)
        #expect(d.name == "demo")
        #expect(d.description == "does things")
    }

    @Test func blockMissingKeysReportsTrueWithNils() {
        let md = "---\nname: demo\n---\n\nbody"
        let d = FrontmatterParser.parseDetailed(markdown: md)
        #expect(d.hasFrontmatter == true)
        #expect(d.name == "demo")
        #expect(d.description == nil)
    }

    @Test func unterminatedBlockReportsFalse() {
        let d = FrontmatterParser.parseDetailed(markdown: "---\nname: demo\n\nbody")
        #expect(d.hasFrontmatter == false)
    }

    /// 空 description 归一为 nil（健康检查把空串视为缺失）。
    @Test func emptyValuesNormalizeToNil() {
        let md = "---\nname: demo\ndescription: \n---\n\nbody"
        let d = FrontmatterParser.parseDetailed(markdown: md)
        #expect(d.hasFrontmatter == true)
        #expect(d.name == "demo")
        #expect(d.description == nil)
    }
}

@Suite struct FingerprintTotalBytesTests {
    /// 多文件目录 totalBytes 求和正确；缓存命中后值仍正确；隐藏文件不计入。
    @Test func totalBytesSumsRegularFiles() throws {
        Fingerprint.clearCache()
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ak-health-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data(Array(repeating: UInt8(0x61), count: 100)).write(to: dir.appendingPathComponent("SKILL.md"))
        try Data(repeating: 0x62, count: 250).write(to: dir.appendingPathComponent("a.txt"))
        try Data(repeating: 0x63, count: 50).write(to: dir.appendingPathComponent("b.txt"))

        let first = Fingerprint.fingerprint(of: dir)
        #expect(first.totalBytes == 400)
        // 二次调用走缓存，值不变
        let second = Fingerprint.fingerprint(of: dir)
        #expect(second.totalBytes == 400)
        // 隐藏文件不计入（agent 不加载）
        try Data(repeating: 0x64, count: 999).write(to: dir.appendingPathComponent(".hidden"))
        Fingerprint.clearCache()
        let third = Fingerprint.fingerprint(of: dir)
        #expect(third.totalBytes == 400)
    }
}

@Suite struct ParseDirectoryHealthTests {
    private func makeSkillDir(_ body: (URL) throws -> Void) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ak-health-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try body(dir)
        return dir
    }
    private func kinds(_ parsed: ParsedSkill?) -> Set<SkillIssueKind> {
        Set((parsed?.issues ?? []).map(\.kind))
    }

    @Test func healthySkillHasNoIssuesAndCarriesSizes() throws {
        let md = "---\nname: demo\ndescription: ok\n---\n\n# Demo\n"
        let dir = try makeSkillDir { dir in
            try Data(md.utf8).write(to: dir.appendingPathComponent("SKILL.md"))
            try Data(repeating: 0x61, count: 20).write(to: dir.appendingPathComponent("a.txt"))
        }
        defer { try? FileManager.default.removeItem(at: dir) }
        let parsed = SkillParsing.parseDirectory(dir)
        #expect(parsed != nil)
        #expect(kinds(parsed).isEmpty)
        #expect(parsed?.totalBytes == 20 + md.utf8.count)
        #expect(parsed?.skillMdBytes == md.utf8.count)
    }

    @Test func emptySkillMdReported() throws {
        let dir = try makeSkillDir { dir in
            try Data().write(to: dir.appendingPathComponent("SKILL.md"))
        }
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(kinds(SkillParsing.parseDirectory(dir)) == [.emptySkillMd])
    }

    @Test func missingFrontmatterReported() throws {
        let dir = try makeSkillDir { dir in
            try Data("# Just body\n".utf8).write(to: dir.appendingPathComponent("SKILL.md"))
        }
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(kinds(SkillParsing.parseDirectory(dir)) == [.missingFrontmatter])
    }

    @Test func missingNameAndDescriptionReported() throws {
        let dir = try makeSkillDir { dir in
            try Data("---\nother: x\n---\n\nbody".utf8).write(to: dir.appendingPathComponent("SKILL.md"))
        }
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(kinds(SkillParsing.parseDirectory(dir)) == [.missingName, .missingDescription])
    }

    @Test func invalidEncodingReported() throws {
        let dir = try makeSkillDir { dir in
            try Data([0xFF, 0xFE, 0xFD]).write(to: dir.appendingPathComponent("SKILL.md"))
        }
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(kinds(SkillParsing.parseDirectory(dir)) == [.invalidEncoding])
    }

    @Test func brokenSymlinkReported() throws {
        let dir = try makeSkillDir { dir in
            try Data("---\nname: demo\ndescription: ok\n---\n\nbody".utf8)
                .write(to: dir.appendingPathComponent("SKILL.md"))
            try FileManager.default.createSymbolicLink(
                at: dir.appendingPathComponent("dangling"),
                withDestinationURL: dir.appendingPathComponent("no-such-target")
            )
        }
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(kinds(SkillParsing.parseDirectory(dir)) == [.brokenSymlink])
    }
}
