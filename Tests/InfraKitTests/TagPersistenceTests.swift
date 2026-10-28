import Foundation
import Testing
import DomainKit
@testable import InfraKit

/// 5.2：assignment key（skillID）跨禁用/恢复不变，TagStore 关联保留。
@Suite struct TagPersistenceTests {
    @Test func assignmentSurvivesDisableEnableCycle() throws {
        let home = makeFakeHome(files: [
            "a/.claude/skills/review/SKILL.md",
            "scratch/.keep",
        ])
        defer { cleanup(home) }
        let base = home.appendingPathComponent("ak", isDirectory: true)
        let skillDirectory = home.appendingPathComponent("a/.claude/skills/review", isDirectory: true)
        try "---\nname: review\ndescription: review\n---\n正文\n".write(
            to: skillDirectory.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8
        )

        // 目录是 skill 的识别规则：收集器可发现（此处直接按 CatalogBuilder 同规则取 skillID）
        let parsed = SkillParsing.parseDirectory(skillDirectory)
        #expect(parsed != nil)

        let lifecycle = SkillLifecycle(baseDirectory: base)
        let tagStore = TagStore(directory: base)

        // 禁用：目录进禁用区（skillID 对应路径消失）
        let record = try lifecycle.disable(agentID: "claude-code", skillDirectory: skillDirectory)
        #expect(!FileManager.default.fileExists(atPath: skillDirectory.path))
        // TagStore 无感知保留（持久层不依赖文件系统）——先赋值再禁用也不丢（先赋值）
        tagStore.addDefinition("写作")
        tagStore.assign(tag: "写作", skillID: skillDirectory.standardizedFileURL.path)

        // 恢复：回到原路径（manifest originalPath），skillID 与禁用前一致
        try lifecycle.enable(agentID: "claude-code", name: "review")
        #expect(record.originalPath == skillDirectory.standardizedFileURL.path)
        try? "恢复后内容".write(
            to: skillDirectory.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8
        )
        #expect(tagStore.tags(forSkillID: skillDirectory.standardizedFileURL.path) == ["写作"])
    }
}
