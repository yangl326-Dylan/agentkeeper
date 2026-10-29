import Foundation
import Testing
@testable import AgentKeeperUI

/// SKILL.md 块级解析：标题/段落/代码围栏/列表/引用/分隔线。
@Suite struct MarkdownBlockParserTests {
    @Test func headingsWithLevels() {
        let blocks = MarkdownBlockParser.parse("# 大标题\n## 小节\n### 三级")
        #expect(blocks == [
            .heading(level: 1, text: "大标题"),
            .heading(level: 2, text: "小节"),
            .heading(level: 3, text: "三级"),
        ])
    }

    @Test func blankLinesSplitParagraphs() {
        let blocks = MarkdownBlockParser.parse("第一段第一行\n连行。\n\n第二段。")
        #expect(blocks == [
            .paragraph(text: "第一段第一行\n连行。"),
            .paragraph(text: "第二段。"),
        ])
    }

    @Test func codeFenceKeepsLanguageAndVerbatimBody() {
        let source = "```swift\nlet x = 1\n#if A\n#endif\n```"
        #expect(MarkdownBlockParser.parse(source) == [
            .code(language: "swift", text: "let x = 1\n#if A\n#endif")
        ])
    }

    @Test func unclosedCodeFenceRunsToEnd() {
        let blocks = MarkdownBlockParser.parse("```bash\ngrep -r foo")
        #expect(blocks == [.code(language: "bash", text: "grep -r foo")])
    }

    @Test func listItemsCollectRepeatAndDistinguishOrdered() {
        let blocks = MarkdownBlockParser.parse("- 甲\n- 乙\n\n1. 第一步\n2. 第二步")
        #expect(blocks == [
            .list(items: ["甲", "乙"], ordered: false),
            .list(items: ["第一步", "第二步"], ordered: true),
        ])
    }

    @Test func blockquoteAndRule() {
        let blocks = MarkdownBlockParser.parse("> 引用一句\n\n---\n***")
        #expect(blocks == [
            .quote(text: "引用一句"),
            .rule,
            .rule,
        ])
    }

    @Test func listInsideCodeFenceIsVerbatim() {
        // 围栏内的 # / - 不得被误判为块结构
        let blocks = MarkdownBlockParser.parse("```\n# 不是标题\n- 不是列表\n```")
        #expect(blocks == [.code(language: "", text: "# 不是标题\n- 不是列表")])
    }

    @Test func inlineMarkdownSurvivesInText() {
        let blocks = MarkdownBlockParser.parse("见 **粗体** 与 `代码`。")
        #expect(blocks == [.paragraph(text: "见 **粗体** 与 `代码`。")])
    }
}
