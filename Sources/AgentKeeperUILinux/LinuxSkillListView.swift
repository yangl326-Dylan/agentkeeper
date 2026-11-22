#if os(Linux)
import Foundation
import SwiftCrossUI
import AgentKeeperShared
import AppCore
import DomainKit
import InfraKit

/// 列表列：工具行（扫描/导入/设置 + agent 切换）→ 过滤 TextField → Skill 列表 / 生命周期区视图。
/// 成对文件：Sources/AgentKeeperUI/RootView.swift 的 SkillListView（macOS .searchable/.toolbar
/// 无 SCUI 对应物 → TextField + 页内工具行重构，报告 §4.3 映射结论）。
struct LinuxSkillListView: View {
    let env: AppEnvironment
    /// 打开设置窗口（SCUI Settings 场景无对应物 → 独立 Window + openWindow）。
    let openSettings: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            toolbar
            if case let .zone(zone) = env.selectedNode {
                LinuxZoneListView(env: env, zone: zone)
            } else {
                filterField
                listBody
            }
        }
        .padding(10)
        .background(LinuxPalette.background)
    }

    // MARK: 工具行

    private var toolbar: some View {
        let l = env.l10n
        let running = env.store.state.scan.phase == .running
        return HStack(spacing: 8) {
            LinuxToolbarButton(label: running ? l.scanning : l.scanNow) {
                Task { await env.scanNow() }
            }
            .disabled(running)
            .help(l.scanNow)
            LinuxToolbarButton(label: l.importSkill) {
                Task { await importFromPicker() }
            }
            .help(l.importSkill)
            LinuxToolbarButton(label: l.settingsMenu) {
                openSettings()
            }
            .help(l.settingsMenu)
            Spacer(minLength: 8)
            agentPicker
        }
    }

    /// agent 切换（macOS 侧栏 agent 行的等价入口：切到该 agent 视图并清空选中与搜索；
    /// 「所有 Skills」选项回根视图）。Gtk3Backend 的 Picker 未实现 → Menu 等价表达。
    private var agentPicker: some View {
        let options = agentOptions
        let current = currentAgentOption(from: options)
        return Menu(current.label) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                Button(option.label) {
                    if let agentID = option.agentID {
                        env.openAgentFilter(agentID)
                    } else {
                        env.select(node: .all)
                    }
                }
            }
        }
        .frame(maxWidth: 200)
    }

    private func currentAgentOption(from options: [AgentFilterOption]) -> AgentFilterOption {
        if case let .agent(id) = env.selectedNode {
            return options.first { $0.agentID == id } ?? options[0]
        }
        return options[0]
    }

    private var agentOptions: [AgentFilterOption] {
        var options = [AgentFilterOption(agentID: nil, label: env.l10n.sidebarAllSkills)]
        options.append(contentsOf: env.sidebarRows().map { row in
            AgentFilterOption(agentID: row.id, label: row.name)
        })
        return options
    }

    // MARK: 过滤（.searchable 替代）

    private var filterField: some View {
        TextField(env.l10n.searchPrompt, text: Binding(
            get: { env.searchText },
            set: { env.searchText = $0 }
        ))
    }

    // MARK: 列表

    @ViewBuilder
    private var listBody: some View {
        let query = linuxFilteredSkills(env.searchText, env)
        if query.isEmpty {
            ContentUnavailableView {
                Text(env.l10n.noMatchingSkills)
            } description: {
                Text(env.l10n.adjustFilterOrRescan)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(query, selection: Binding<String?>(
                get: { env.selectedSkillID },
                set: { env.selectedSkillID = $0 }
            )) { skill in
                LinuxSkillRowView(skill: skill, l10n: env.l10n)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: 导入（zenity 目录选择 → env.importSkill；失败 alert 非阻断呈现语义 → 状态行文案）

    private func importFromPicker() async {
        guard let directory = await env.adapter.openDirectoryPicker() else { return }
        guard let targetRoot = currentTargetRoot() else { return }
        await env.importSkill(from: directory, targetSkillRoot: targetRoot)
    }

    /// 导入目标 skill 根默认值：第一个已安装 agent 的第一个用户级 skill 根（对齐 macOS）。
    private func currentTargetRoot() -> URL? {
        for agent in env.store.state.agents {
            if let root = agent.skillRoots.first {
                return root.path
            }
        }
        return nil
    }
}

/// 工具行按钮：显式单行标签 + 最小宽度。
/// （Gtk3 的 `Button(String)` 在窄列表列里会被压成逐字换行——见实装截图验证。）
struct LinuxToolbarButton: View {
    let label: String
    let action: @MainActor @Sendable () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .lineLimit(1)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
        }
        .fixedSize(horizontal: true, vertical: false)
        .frame(minWidth: 64)
    }
}

/// agent 切换菜单选项（Gtk3Backend 无 Picker → Menu 等价表达；
/// 包装类型随界面语言在渲染期重建，语言切换即刷新）。
struct AgentFilterOption: Equatable, CustomStringConvertible {
    let agentID: String?
    let label: String

    var description: String { label }
}

// MARK: - 列表行

/// Skill 列表行：状态符号（颜色语义对齐 StatusSemantics）+ 名称/副标题 + 作用域徽章。
/// 成对文件：RootView.swift 的 SkillRowView。
struct LinuxSkillRowView: View {
    let skill: Skill
    var l10n: L10n = L10n(lang: .zhHans)

    var body: some View {
        let token: StatusToken = skill.status == .disabled ? .disabled : .enabled
        let semantics = StatusSemantics.resolve(token)
        HStack(spacing: 8) {
            Text(LinuxStatusGlyph.symbol(for: token))
                .font(.system(size: 10))
                .foregroundColor(LinuxPalette.semantic(semantics.colorKey))
                .help(semantics.explanation)
            VStack(alignment: .leading, spacing: 2) {
                Text(skill.name)
                    .font(.body)
                    .foregroundColor(LinuxPalette.textPrimary)
                Text(subtitle(skill))
                    .font(.caption)
                    .foregroundColor(LinuxPalette.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if !skill.issues.isEmpty {
                Text("▲")
                    .font(.system(size: 10))
                    .foregroundColor(LinuxPalette.amber)
                    .help(l10n.healthBadgeHelp)
            }
            Text(l10n.scopeBadge(skill.scope))
                .font(.caption2)
                .foregroundColor(LinuxPalette.textSecondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(LinuxPalette.subtle)
        }
        .padding(.vertical, 2)
    }

    private func subtitle(_ skill: Skill) -> String {
        var parts: [String] = []
        // 全局/同铺设 skill 拥有多个 owner——只显示第一个会誤导（看似专属）
        let owners = skill.owners.joined(separator: l10n.listSeparator)
        if !owners.isEmpty { parts.append(owners) }
        if let desc = skill.skillDescription, !desc.isEmpty { parts.append(desc) }
        return parts.joined(separator: " · ")
    }
}

// MARK: - 生命周期区视图

/// 停用区/回收站列表：恢复 + 彻底删除（彻底删除/清空带确认 alert——SCUI alert 官方支持，
/// 语义对齐 macOS confirmationDialog）。
/// 成对文件：Sources/AgentKeeperUI/ZoneListView.swift。
struct LinuxZoneListView: View {
    let env: AppEnvironment
    let zone: LifecycleZone
    /// 彻底删除确认（非 nil → 弹确认，标题随行构建）。
    @State private var pendingPurge: ZoneRowModel?
    /// 清空回收站确认。
    @State private var pendingEmpty = false

    var body: some View {
        let l = env.l10n
        let rows = zone == .disabled ? env.disabledZoneRows() : env.trashedZoneRows()
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                if rows.isEmpty {
                    Text(zone == .disabled ? l.zoneDisabledEmpty : l.zoneTrashEmpty)
                        .font(.body)
                        .foregroundColor(LinuxPalette.textSecondary)
                        .padding(12)
                } else {
                    ForEach(rows) { row in
                        LinuxZoneRowView(
                            env: env,
                            zone: zone,
                            row: row,
                            onRequestPurge: { pendingPurge = $0 }
                        )
                    }
                    if zone == .trash {
                        Button(l.zoneEmptyTrash) {
                            pendingEmpty = true
                        }
                        .help(l.zoneEmptyTrashHelp)
                        .padding(.top, 8)
                    }
                }
            }
            .padding(2)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // 彻底删除确认（不可恢复）。SCUI alert 无独立 message 参数 → 正文并入标题
        // （两行呈现；语义与 macOS confirmationDialog 的 title+message 对齐）。
        .alert(
            Binding(
                get: {
                    pendingPurge.map {
                        l.zonePurgeTitle($0.name) + "\n" + l.zonePurgeMessage($0.originalPath)
                    }
                },
                set: { if $0 == nil { pendingPurge = nil } }
            )
        ) {
            Button(l.commonCancel) {}
            Button(l.zonePurgeButton) {
                guard let row = pendingPurge else { return }
                pendingPurge = nil
                Task { await env.purgeTrashEntry(row) }
            }
        }
        // 清空回收站确认（不可恢复）。同上：正文并入标题。
        .alert(
            Binding(
                get: {
                    pendingEmpty
                        ? l.zoneEmptyTrashTitle(rows.count) + "\n" + l.zoneEmptyTrashMessage
                        : nil
                },
                set: { if $0 == nil { pendingEmpty = false } }
            )
        ) {
            Button(l.commonCancel) {}
            Button(l.zoneEmptyButton) {
                pendingEmpty = false
                Task { await env.purgeAllTrash() }
            }
        }
    }
}

/// 区行：名称/agent/原路径/停用时间 + 恢复（回收站另含彻底删除）。
struct LinuxZoneRowView: View {
    let env: AppEnvironment
    let zone: LifecycleZone
    let row: ZoneRowModel
    /// 彻底删除经确认弹窗（视图层负责确认，env 注释同语义）。
    let onRequestPurge: (ZoneRowModel) -> Void

    var body: some View {
        let l = env.l10n
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                    .font(.body)
                    .foregroundColor(LinuxPalette.textPrimary)
                HStack(spacing: 6) {
                    Text(row.agentID)
                    if let date = row.disabledAt {
                        Text(zone == .disabled ? l.zoneDisabledAt : l.zoneDeletedAt)
                        Text(Self.dateText(date))
                    }
                    Text(row.originalPath)
                        .lineLimit(1)
                }
                .font(.caption)
                .foregroundColor(LinuxPalette.textSecondary)
            }
            Spacer(minLength: 0)
            Button(zone == .disabled ? l.zoneEnableButton : l.zoneRestoreButton) {
                Task { await env.enableFromZone(zone: zone, row: row) }
            }
            .help(l.zoneRestoreHelp)
            if zone == .trash {
                Button(l.zonePurgeButton) {
                    onRequestPurge(row)
                }
                .help(l.zonePurgeRowHelp)
            }
        }
        .padding(6)
        .background(LinuxPalette.card)
    }

    private static func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }
}

// MARK: - 列表筛选（共享逻辑收口）

/// 筛选逻辑：与 macOS RootView/SkillListCore.filter 同一组合语义——
/// 侧栏节点（NavigationModel.catalogQuery）∩ 搜索词；标签节点合成禁用条目。
/// 共享 VM 剥离（任务 2.4）暂缓期间两侧各持一份薄组合，引用同一 AppCore 纯函数。
@MainActor
func linuxFilteredSkills(_ searchText: String, _ env: AppEnvironment) -> [Skill] {
    guard var query = NavigationModel.catalogQuery(for: env.selectedNode) else { return [] }
    query.searchText = searchText
    let isTagNode: Bool = {
        if case .tag = env.selectedNode { return true }
        return false
    }()
    let catalog = isTagNode ? env.catalogForTagFilter() : env.catalogStore.current
    // 无标签筛选时不取标签映射（避免 N 次串行队列锁往返，对齐 macOS 注释）
    let tags = isTagNode ? env.tagsBySkill() : [:]
    return query.apply(catalog: catalog, tagsBySkill: tags)
}
#endif
