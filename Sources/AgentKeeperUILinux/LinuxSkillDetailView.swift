#if os(Linux)
import Foundation
import SwiftCrossUI
import AgentKeeperShared
import AppCore
import DomainKit
import InfraKit

/// 详情面板：未选中 → 总览仪表盘；选中 → skill 元数据/操作/文件清单/目录大小/SKILL.md 预览。
/// 成对文件：Sources/AgentKeeperUI/RootView.swift 的 SkillDetailView/SkillDetailContent
/// （v1 范围：任务 3.4 指定的区块；标签/历史/快照/同名安装区留待后续小步补齐）。
///
/// 结构注意：条件分支放在 ScrollView **内部**（单一稳定视图类型为根）。
/// SCUI Gtk3Backend 实测：EitherView 位于分栏 detail 槽位时，case 切换后新插入的
/// 弹性尺寸子树（ScrollView）不渲染（窗口空白，resize 也不恢复）；把 if/else 收进
/// ScrollView 内容里可绕开——切换只发生在已布局的 GtkFixed 容器内，渲染正常。
struct LinuxSkillDetailView: View {
    let env: AppEnvironment

    // 预览数据异步加载（task(id:) 切换 skill 时先清空 → 加载占位）
    @State private var markdown: String?
    @State private var files: [SkillPreviewModel.FileListEntry]?
    @State private var directorySize: Int64?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let skill = selectedSkill {
                    LinuxSkillDetailSections(
                        env: env,
                        skill: skill,
                        markdown: markdown,
                        files: files,
                        directorySize: directorySize
                    )
                } else {
                    LinuxOverviewDashboard(env: env)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LinuxPalette.background)
        .task(id: env.selectedSkillID) {
            // 切换 skill：立即清空旧数据（避免停留在上一个），再后台并行加载
            guard let skill = selectedSkill else {
                markdown = nil
                files = nil
                directorySize = nil
                return
            }
            markdown = nil
            files = nil
            directorySize = nil
            async let md = skill.layout == .flatFile
                ? SkillPreviewModel.loadMarkdownFile(skill.directory)
                : SkillPreviewModel.loadMarkdown(skillDir: skill.directory)
            async let fs = skill.layout == .flatFile
                ? SkillPreviewModel.loadFlatFileEntry(skill.directory)
                : SkillPreviewModel.loadFiles(skillDir: skill.directory)
            async let size = SkillPreviewModel.loadDirectorySize(skill.directory)
            // 空串哨兵 = SKILL.md 缺失（nil = 加载中；占位文案按语言渲染）
            (markdown, files, directorySize) = await (md ?? "", fs, size)
        }
    }

    private var selectedSkill: Skill? {
        guard let id = env.selectedSkillID else { return nil }
        return env.catalogStore.current.first { $0.id == id }
    }
}

/// Skill 详情区块（header/作用域/文件清单/预览；无滚动容器——由外层统一提供，
/// env 显式注入；区块拆出后父视图持有异步状态，切 skill 即整体重建）。
struct LinuxSkillDetailSections: View {
    let env: AppEnvironment
    let skill: Skill
    let markdown: String?
    let files: [SkillPreviewModel.FileListEntry]?
    let directorySize: Int64?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            scopeSection
            Divider()
            filesSection
            Divider()
            previewSection
        }
    }

    // MARK: 头部（符号/名称/描述/路径）

    private var header: some View {
        let semantics = StatusSemantics.resolve(skill.status == .disabled ? .disabled : .enabled)
        return HStack(alignment: .top, spacing: 12) {
            Text(LinuxStatusGlyph.symbol(for: skill.status == .disabled ? .disabled : .enabled))
                .font(.system(size: 26))
                .foregroundColor(LinuxPalette.semantic(semantics.colorKey))
                .help(semantics.explanation)
            VStack(alignment: .leading, spacing: 4) {
                Text(skill.name)
                    .font(.title2)
                    .emphasized()
                    .foregroundColor(LinuxPalette.textPrimary)
                if let desc = skill.skillDescription, !desc.isEmpty {
                    Text(desc)
                        .font(.callout)
                        .foregroundColor(LinuxPalette.textSecondary)
                        .lineLimit(3)
                }
                Text(skill.directory.path)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(LinuxPalette.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: 作用域 + 操作

    private var scopeSection: some View {
        let l = env.l10n
        let isDisabled = skill.status == .disabled
        let pending = env.store.state.operation
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(l.scopeDetailText(skill.scope))
                    .font(.caption)
                    .foregroundColor(LinuxPalette.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(LinuxPalette.subtle)
                Text("sha256 \(String(skill.sha256.prefix(12)))…")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(LinuxPalette.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let size = directorySize {
                    Text(Self.sizeText(size))
                        .font(.caption)
                        .foregroundColor(LinuxPalette.textSecondary)
                        .help(l10nFilesSize)
                }
            }
            if skill.layout == .flatFile {
                Text(l.flatReadOnlyNotice)
                    .font(.caption)
                    .foregroundColor(LinuxPalette.textSecondary)
            } else {
                HStack(spacing: 8) {
                    Button(isDisabled ? l.opEnable : l.opDisable) {
                        Task { await env.runOperation(skill: skill, direction: isDisabled ? .enable : .disable) }
                    }
                    .disabled(pending.inFlight != nil)
                    .help(pending.failureMessage ?? (isDisabled ? l.enableHelp : l.disableHelp))
                    Button(l.opMoveToTrash) {
                        Task { await env.runOperation(skill: skill, direction: .delete) }
                    }
                    .disabled(pending.inFlight != nil)
                    .help(l.moveToTrashHelp)
                    Button(l.showInFinder) {
                        env.adapter.revealInFileManager(skill.directory)
                    }
                    .help(l.showInFinder)
                }
            }
        }
    }

    /// 「目录大小」标签（Linux 界内新增文案——Shared L10n 无此键，AppCore 只读边界，
    /// 文案落本栈双语）。
    private var l10nFilesSize: String {
        env.l10n.lang == .zhHans ? "目录大小" : "Directory size"
    }

    // MARK: 文件清单

    @ViewBuilder
    private var filesSection: some View {
        let l = env.l10n
        VStack(alignment: .leading, spacing: 6) {
            Text(l.filesList(files?.count ?? 0))
                .font(.headline)
                .foregroundColor(LinuxPalette.textPrimary)
            if let files {
                // 不用嵌套 ScrollView（Gtk3Backend 实测嵌套 ScrolledWindow 渲染不稳）；
                // 文件多时由外层详情滚动容器统一承载，卡片高度随内容自适应。
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(files, id: \.path) { entry in
                        HStack(spacing: 6) {
                            Text(entry.isDirectory ? "▸" : "·")
                                .font(.system(size: 11))
                                .foregroundColor(LinuxPalette.textSecondary)
                            Text(entry.path)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(LinuxPalette.textPrimary)
                                .lineLimit(1)
                        }
                        .onTapGesture {
                            // 双击语义 v1 简化：单击即在文件管理器中定位
                            env.adapter.revealInFileManager(
                                skill.directory.appendingPathComponent(entry.path)
                            )
                        }
                    }
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(LinuxPalette.card)
            } else {
                loadingPlaceholder(l.detailListingFiles)
            }
        }
    }

    // MARK: SKILL.md 预览

    @ViewBuilder
    private var previewSection: some View {
        let l = env.l10n
        VStack(alignment: .leading, spacing: 6) {
            Text(l.detailPreview)
                .font(.headline)
                .foregroundColor(LinuxPalette.textPrimary)
            if let markdown {
                if markdown.isEmpty {
                    Text(l.markdownMissing)
                        .font(.body)
                        .foregroundColor(LinuxPalette.textSecondary)
                } else {
                    LinuxMarkdownDocumentView(markdown: markdown)
                }
            } else {
                loadingPlaceholder(l.detailReadingSkillMd)
            }
        }
    }

    /// 异步加载中的占位（切换 skill 的加载反馈；减少动效 → 静态文案）。
    private func loadingPlaceholder(_ text: String) -> some View {
        let motion = linuxMotionPolicy(for: env)
        return HStack(spacing: 8) {
            if motion.showsScanSpinner {
                ProgressView()
                    .frame(width: 12, height: 12)
            } else {
                Text("◐")
                    .font(.system(size: 11))
                    .foregroundColor(LinuxPalette.textSecondary)
            }
            Text(text)
                .font(.caption)
                .foregroundColor(LinuxPalette.textSecondary)
        }
        .padding(.vertical, 6)
    }

    // MARK: 辅助

    /// 字节数 → 人类可读（KB/MB；Linux 界内辅助）。
    static func sizeText(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - 目录大小（异步后台统计）

extension SkillPreviewModel {
    /// skill 目录总大小（字节；后台递归统计——详情面板元数据展示用，Linux v1 新增）。
    static func loadDirectorySize(_ directory: URL) async -> Int64 {
        let rootPath = URL(fileURLWithPath: directory.path).standardizedFileURL.path
        return await Task.detached(priority: .utility) {
            guard let enumerator = FileManager.default.enumerator(
                at: URL(fileURLWithPath: rootPath, isDirectory: true),
                includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileSizeKey],
                options: []
            ) else { return 0 }
            var total: Int64 = 0
            for case let url as URL in enumerator {
                // 目录条目无大小 → 0；文件取占用/名义大小
                let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey])
                total += Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
            }
            return total
        }.value
    }
}

// MARK: - Markdown 块级渲染（解析共享 MarkdownBlockParser + SCUI 分级呈现）

/// SKILL.md 块级渲染（v1：标题/段落/代码/列表/引用/分隔线分级字体呈现；
/// 行内 **粗体**/`代码` 不做 span 级解析——成对文件：MarkdownDocument.swift）。
struct LinuxMarkdownDocumentView: View {
    let markdown: String
    /// 围栏内原样文本（解析器已保证）；按行渲染 monospaced。
    var body: some View {
        let blocks = MarkdownBlockParser.parse(markdown)
        VStack(alignment: .leading, spacing: 10) {
            ForEach(blocks.indices, id: \.self) { index in
                linuxMarkdownBlock(blocks[index])
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func linuxMarkdownBlock(_ block: MarkdownBlockParser.MarkdownBlock) -> some View {
        switch block {
        case let .heading(level, text):
            Text(text)
                .font(headingFont(level))
                .emphasized()
                .foregroundColor(LinuxPalette.textPrimary)
                .padding(.top, level <= 2 ? 6 : 2)
        case let .paragraph(text):
            Text(text)
                .font(.body)
                .foregroundColor(LinuxPalette.textPrimary)
                .lineLimit(nil)
        case let .code(_, text):
            Text(text)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(LinuxPalette.textPrimary)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(LinuxPalette.subtle)
        case let .list(items, ordered):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(items.indices, id: \.self) { index in
                    HStack(alignment: .top, spacing: 6) {
                        Text(ordered ? "\(index + 1)." : "•")
                            .font(.body)
                            .foregroundColor(LinuxPalette.textSecondary)
                        Text(items[index])
                            .font(.body)
                            .foregroundColor(LinuxPalette.textPrimary)
                            .lineLimit(nil)
                    }
                }
            }
        case let .quote(text):
            HStack(alignment: .top, spacing: 0) {
                Color(hex: LinuxPalette.accentHex)
                    .frame(width: 3)
                Text(text)
                    .font(.callout)
                    .foregroundColor(LinuxPalette.textSecondary)
                    .padding(.leading, 8)
                    .lineLimit(nil)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .rule:
            Divider()
        }
    }

    /// 标题分级字体（# 大 → ###### 小）。
    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: .title
        case 2: .title3
        case 3: .headline
        default: .subheadline
        }
    }
}
#endif
