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
