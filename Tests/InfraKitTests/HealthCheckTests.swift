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
