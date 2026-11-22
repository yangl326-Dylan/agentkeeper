import Foundation

/// Markdown 块级文档解析（SKILL.md 预览：解析共享、渲染分栈）。
public enum MarkdownBlockParser {
    /// 块级元素（行内 **粗体**/`代码` 等交给各栈渲染层）。
    public enum MarkdownBlock: Equatable, Sendable {
        case heading(level: Int, text: String)
        case paragraph(text: String)
        case code(language: String, text: String)
        case list(items: [String], ordered: Bool)
        case quote(text: String)
        case rule

        var isBlankSeparator: Bool { false }
    }

    /// 把 markdown 源码切成块。规则（YAGNI 有意子集）：
    /// - `#`-`######` 标题；空行分段；连续正文行合并进同一段
    /// - 无修饰围栏（```）与波浪线围栏（~~~）之间的行保持原样
    /// - `- `/`* `/`N. ` 开头条目连续聚合为列表（围栏内不适用）
    /// - `> ` 引用；`---`/`***`/`___` 分隔线
    public static func parse(_ source: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []

        var fenceMarker: Character? = nil
        var fenceLines: [String] = []
        var fenceLanguage = ""
        func fenceFeedback() {
            if fenceMarker != nil {
                blocks.append(.code(language: fenceLanguage, text: fenceLines.joined(separator: "\n")))
            }
            fenceMarker = nil
            fenceLines = []
            fenceLanguage = ""
        }

        var paragraphLines: [String] = []
        var listItems: [String] = []
        var listOrdered = false
        func paragraphFeedback() {
            if !paragraphLines.isEmpty {
                blocks.append(.paragraph(text: paragraphLines.joined(separator: "\n")))
                paragraphLines = []
            }
        }
        func listFeedback() {
            if !listItems.isEmpty {
                blocks.append(.list(items: listItems, ordered: listOrdered))
                listItems = []
                listOrdered = false
            }
        }
        func breakAll() {
            paragraphFeedback()
            listFeedback()
        }
        let isRule: (String) -> Bool = { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.count >= 3 && trimmed.allSatisfy { $0 == "-" || $0 == "*" || $0 == "_" }
        }
        let listPrefix: (String) -> (Bool, String)? = { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
                return (false, String(trimmed.dropFirst(2)))
            }
            // 有序："N. "（点号前至少一位纯数字）
            if let dot = trimmed.firstIndex(of: ".") {
                let next = trimmed.index(after: dot)
                if next < trimmed.endIndex, trimmed[next] == " " {
                    let digits = trimmed[trimmed.startIndex..<dot]
                    if !digits.isEmpty && digits.allSatisfy({ $0.isNumber }) {
                        return (true, String(trimmed[trimmed.index(after: next)...]))
                    }
                }
            }
            return nil
        }

        for rawLine in source.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)

            // 围栏状态
            if let marker = fenceMarker {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.count >= 3 && trimmed.allSatisfy({ $0 == marker }) {
                    fenceFeedback()
                } else {
                    fenceLines.append(line)
                }
                continue
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // 开围栏：```/~~~ + 可选语言后缀
            if fenceMarker == nil, trimmed.count >= 3,
               let marker = trimmed.first, marker == "`" || marker == "~",
               trimmed.allSatisfy({ $0 == marker || $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) {
                breakAll()
                fenceMarker = marker
                fenceLanguage = String(trimmed.drop(while: { $0 == marker }))
                // 纯围栏符视为无语言
                if fenceLanguage.allSatisfy({ $0 == marker }) { fenceLanguage = "" }
                continue
            }

            if trimmed.isEmpty {
                breakAll()
                continue
            }

            if isRule(line) {
                breakAll()
                blocks.append(.rule)
                continue
            }

            if line.hasPrefix("#") {
                let hashes = line.prefix { $0 == "#" }
                let level = hashes.count
                if level <= 6, level < line.count {
                    breakAll()
                    let title = String(line.dropFirst(level))
                        .trimmingCharacters(in: .whitespaces)
                    blocks.append(.heading(level: level, text: title))
                    continue
                }
            }

            let listed = listPrefix(line)
            if let (ordered, item) = listed {
                paragraphFeedback()
                if !listItems.isEmpty && ordered != listOrdered {
                    listFeedback()
                }
                listOrdered = ordered
                listItems.append(item)
                continue
            }

            if line.hasPrefix(">") {
                breakAll()
                let content = line.dropFirst(1).drop { $0 == " " }
                blocks.append(.quote(text: String(content)))
                continue
            }

            // 正文行：若之前有悬置列表先收；段落行连续累积（空行才分段）
            listFeedback()
            paragraphLines.append(line)
        }
        // EOF 收尾：围栏未闭合也保持原样（unclosed → 保留）
        fenceFeedback()
        breakAll()
        return blocks
    }
}
