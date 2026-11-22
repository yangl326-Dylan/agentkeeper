#if os(Linux)
import SwiftCrossUI
import AgentKeeperShared
import AppCore
import DomainKit

/// 三面板主壳：侧栏（导航树）→ 列表（筛选/搜索）→ 详情。
/// 成对文件：Sources/AgentKeeperUI/RootView.swift（macOS 栈，交互语义的权威参照）。
/// SCUI 布局映射：NavigationSplitView(sidebar:content:detail:)（嵌套 Gtk paned）；
/// macOS 工具条（.toolbar 无对应物）落为列表列顶部工具行（报告 §4.3 映射结论）。
public struct LinuxRootView: View {
    public let env: AppEnvironment
    @Environment(\.openWindow) private var openWindow
    /// 托盘挂载结果（false → 界内降级提示，spec 降级场景）。
    @State private var trayAvailable = true

    public init(env: AppEnvironment) {
        self.env = env
    }

    public var body: some View {
        NavigationSplitView {
            LinuxNavigationSidebar(env: env, trayAvailable: trayAvailable)
        } content: {
            LinuxSkillListView(env: env, openSettings: { openWindow(id: "settings") })
                // 列表列最小宽度：SCUI 的 Gtk paned 默认按内容压缩，工具行会被挤成竖排
                // （实装截图验证）；340pt 保证三按钮 + agent 菜单同排可读。
                .frame(minWidth: 340)
        } detail: {
            LinuxSkillDetailView(env: env)
        }
        .task {
            await env.bootstrap()
            // 托盘：摘要行 + 打开主窗口（经协调器中转 SCUI openWindow）+ 立即扫描 + 退出
            let l = env.l10n
            let summary = "\(env.catalogStore.current.count) skills · \(env.sidebarRows().count) agents"
            let descriptor = TrayDescriptor(
                summary: summary,
                openMainWindowTitle: l.menuOpenMain,
                scanNowTitle: l.scanNow,
                quitTitle: l.menuQuit
            )
            let actions = TrayActions(
                openMainWindow: { LinuxTrayCoordinator.shared.activateMainWindow() },
                scanNow: { [env] in Task { await env.scanNow() } }
            )
            trayAvailable = env.adapter.mountTray(descriptor, actions: actions)
            LinuxTrayCoordinator.shared.registerOpenMainWindow { openWindow(id: "main") }
        }
    }
}

// MARK: - 侧栏（导航树）

/// 侧栏：所有 Skills / Agents / 作用域 / 标签 / 生命周期 + 底部扫描状态条。
/// 全侧栏单选；行模型/env memoize 与 macOS 同源（sidebarRows 等）。
struct LinuxNavigationSidebar: View {
    let env: AppEnvironment
    let trayAvailable: Bool

    var body: some View {
        let l = env.l10n
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                // 「所有 Skills」根节点：选中态永远有落点（spec：显式默认视图）
                LinuxSidebarRow(
                    env: env,
                    node: .all,
                    glyph: "■",
                    glyphColor: LinuxPalette.textSecondary,
                    title: l.sidebarAllSkills,
                    count: env.catalogStore.current.count
                )
                LinuxSidebarSectionHeader(title: l.sectionAgents)
                let rows = env.sidebarRows()
                if rows.isEmpty {
                    Text(l.sidebarNoAgents)
                        .font(.caption)
                        .foregroundColor(LinuxPalette.textSecondary)
                        .padding(.horizontal, 10)
                } else {
                    ForEach(rows) { row in
                        LinuxSidebarRow(
                            env: env,
                            node: .agent(row.id),
                            glyph: LinuxStatusGlyph.agentSymbol(available: row.status == .available),
                            glyphColor: row.status == .available ? LinuxPalette.green : LinuxPalette.amber,
                            title: row.name,
                            subtitle: l.agentRowStatus(available: row.status == .available, skillCount: row.skillCount),
                            count: row.skillCount
                        )
                    }
                }
                LinuxSidebarSectionHeader(title: l.sectionScopes)
                ForEach(sections) { section in
                    LinuxSidebarRow(
                        env: env,
                        node: section.kind == .global ? .global : .project(section.title),
                        glyph: sectionIcon(section.kind),
                        glyphColor: LinuxPalette.textSecondary,
                        title: section.kind == .global ? l.scopeGlobal : section.title,
                        count: section.count
                    )
                }
                // 「标签」节（spec 4.x：导航树按标签分组浏览；空节不渲染，与 macOS 同语义）
                let tagSections = NavigationModel.buildTagSections(
                    skills: env.catalogStore.current,
                    tagsBySkill: env.tagsBySkill()
                )
                if !tagSections.isEmpty {
                    LinuxSidebarSectionHeader(title: l.sectionTags)
                    ForEach(tagSections) { section in
                        LinuxSidebarRow(
                            env: env,
                            node: .tag(section.title),
                            glyph: "#",
                            glyphColor: LinuxPalette.textSecondary,
                            title: section.title,
                            count: section.count
                        )
                    }
                }
                LinuxSidebarSectionHeader(title: l.sectionLifecycle)
                ForEach(LifecycleZone.allCases, id: \.self) { zone in
                    let zoneRows = zone == .disabled ? env.disabledZoneRows() : env.trashedZoneRows()
                    LinuxSidebarRow(
                        env: env,
                        node: .zone(zone),
                        glyph: zone == .disabled ? "❚❚" : "▣",
                        glyphColor: LinuxPalette.textSecondary,
                        title: ZoneListModel.zoneTitle(zone: zone, rows: zoneRows, l10n: l),
                        count: zoneRows.count
                    )
                }
                // 托盘降级界内提示（spec：注册失败 → 仅主窗口 + 界内提示）
                if !trayAvailable {
                    Divider()
                    Text(trayUnavailableText(l))
                        .font(.caption)
                        .foregroundColor(LinuxPalette.amber)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                }
                // 底部留白（状态条占位高度）
                Spacer(minLength: 44)
            }
            .padding(6)
        }
        .background(LinuxPalette.background)
        .overlay(alignment: .bottom) {
            LinuxScanStatusStrip(env: env)
        }
    }

    private var sections: [NavigationSection] {
        NavigationModel.buildSections(skills: env.catalogStore.current)
    }

    /// 节图标（文字符号近似 macOS 的 SF Symbols）。
    private func sectionIcon(_ kind: NavigationSectionKind) -> String {
        switch kind {
        case .global: "⌂"
        case .agent: "▢"
        case .project: "▸"
        case .tag: "#"
        }
    }
}

/// 侧栏节标题。
struct LinuxSidebarSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundColor(LinuxPalette.textSecondary)
            .padding(.horizontal, 10)
            .padding(.top, 8)
    }
}

/// 侧栏行（单选导航：选中行 accent 高亮；点击切节点并清列表选中——env.select 同语义）。
struct LinuxSidebarRow: View {
    let env: AppEnvironment
    let node: SidebarNode
    let glyph: String
    let glyphColor: Color
    let title: String
    var subtitle: String?
    var count: Int?

    var body: some View {
        let selected = env.selectedNode == node
        Button {
            env.select(node: node)
        } label: {
            HStack(spacing: 8) {
                Text(glyph)
                    .font(.system(size: 11))
                    .foregroundColor(glyphColor)
                    .frame(width: 14)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.body)
                        .foregroundColor(LinuxPalette.textPrimary)
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundColor(LinuxPalette.textSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if let count {
                    Text("\(count)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(LinuxPalette.textSecondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? LinuxPalette.selection : Color(hex: 0x000000).opacity(0))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 扫描状态条（非阻断）

/// 状态条：完成态必须带时间戳与 skill 数（LinuxScanStatusText 与 macOS ScanStatusText 逐字对齐）。
struct LinuxScanStatusStrip: View {
    let env: AppEnvironment

    var body: some View {
        let l = env.l10n
        let scan = env.store.state.scan
        let skillsCount = env.catalogStore.current.count
        let colorKey = LinuxScanStatusText.colorKey(for: scan)
        let text = LinuxScanStatusText.compact(scan: scan, skillsCount: skillsCount, l10n: l)
        let motion = linuxMotionPolicy(for: env)
        HStack(spacing: 6) {
            if scan.phase == .running, motion.showsScanSpinner {
                ProgressView()
                    .frame(width: 12, height: 12)
            } else {
                Text(LinuxStatusGlyph.scanSymbol(colorKey: colorKey))
                    .font(.system(size: 9))
                    .foregroundColor(LinuxPalette.semantic(colorKey))
            }
            Text(text)
                .font(.caption)
                .foregroundColor(LinuxPalette.textSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(LinuxPalette.card)
        .padding(.bottom, 8)
        .help(l.stripTapOpenMain)
    }
}
#endif
