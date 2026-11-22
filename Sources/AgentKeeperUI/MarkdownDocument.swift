#if os(macOS)
import Foundation
import SwiftUI
import AgentKeeperShared
import AppCore

// MarkdownBlockParser（纯块解析）已移入 AgentKeeperShared（解析共享、渲染分栈）；
// 本文件只保留 macOS SwiftUI 渲染视图。

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

#endif
