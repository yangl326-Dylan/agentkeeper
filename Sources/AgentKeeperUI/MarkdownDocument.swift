import Foundation
import SwiftUI
import AppCore

/// Markdown 块级文档模型（SKILL.md 预览的解析与渲染）。
public enum MarkdownBlockParser {
    /// 块级元素（行内 **粗体**/`代码` 等交给 AttributedString 渲染）。
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

// MARK: - 渲染视图

/// 折叠 + 内滚动限高的 markdown 文档预览。
/// 解析一次缓存（@State）——曾每次 body 求值重新全量解析 markdown；
/// LazyVStack 让长文档块按需渲染。
@MainActor
struct MarkdownDocumentView: View {
    let markdown: String
    let motion: MotionPolicy
    var l10n: L10n = L10n(lang: .zhHans)
    @State private var collapsed = false
    @State private var cachedBlocks: [MarkdownBlockParser.MarkdownBlock]?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Label(l10n.markdownPreview, systemImage: "doc.text")
                    .font(.headline)
                Spacer()
                Button {
                    withAnimation(motion.animation(for: .detailTransition)) {
                        collapsed.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                        Text(collapsed ? l10n.expand : l10n.collapse)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(collapsed ? l10n.expandHelp : l10n.collapseHelp)
            }

            if collapsed {
                Text(firstParagraph)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                            blockView(block)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .frame(maxHeight: 420) // 卡内滚动：详情页整体不再被长文档拉到失控
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(ClaudePalette.card)
                )
            }
        }
        .textSelection(.enabled)
        .task(id: markdown) {
            // markdown 变更：后台重新解析一次（detached——解析是纯 CPU，不占 MainActor）
            cachedBlocks = await Task.detached(priority: .utility) { [markdown] in
                MarkdownBlockParser.parse(markdown)
            }.value
        }
    }

    /// nil（解析中）时暂给空列表——首帧用 markdown 直接算个兜底（首帧无 task 竞争）
    private var blocks: [MarkdownBlockParser.MarkdownBlock] {
        if let cached = cachedBlocks { return cached }
        return []
    }

    private var firstParagraph: String {
        if cachedBlocks == nil {
            // 首帧兜底（task 尚未跑完时）：轻量解析仅首段
            let parsed = MarkdownBlockParser.parse(markdown)
            if case let .paragraph(text)? = parsed.first { return text }
            if case let .heading(_, text)? = parsed.first { return text }
            return markdown
        }
        if case let .paragraph(text)? = cachedBlocks?.first { return text }
        if case let .heading(_, text)? = cachedBlocks?.first { return text }
        return markdown
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlockParser.MarkdownBlock) -> some View {
        switch block {
        case let .heading(level, text):
            Text(inlined(text))
                .font(headingFont(level))
                .foregroundStyle(ClaudePalette.textPrimary)
                .padding(.top, level <= 1 ? 2 : 6)
        case let .paragraph(text):
            Text(inlined(text))
                .frame(maxWidth: .infinity, alignment: .leading)
        case let .code(language, text):
            VStack(alignment: .leading, spacing: 4) {
                if !language.isEmpty {
                    Text(language)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                }
                Text(text)
                    .font(.callout.monospaced())
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 6).fill(.quinary))
        case let .list(items, ordered):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(ordered ? "\(index + 1)." : "•")
                            .foregroundStyle(.secondary)
                            .frame(minWidth: ordered ? nil : 12, alignment: .trailing)
                        Text(inlined(item))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        case let .quote(text):
            HStack(alignment: .top, spacing: 10) {
                Rectangle()
                    .fill(ClaudePalette.accent.opacity(0.6))
                    .frame(width: 3)
                Text(inlined(text))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .rule:
            Divider()
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: .title3.bold()
        case 2: .headline
        case 3: .subheadline.weight(.semibold)
        default: .callout.weight(.semibold)
        }
    }

    /// 行内 markdown（粗体/斜体/代码/链接）交给 AttributedString。
    private func inlined(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}
