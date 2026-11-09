import SwiftUI
import AppCore
import DomainKit
import InfraKit

/// 三面板主壳：侧栏（导航树）→ 列表（筛选/搜索）→ 详情。
public struct RootView: View {
    public init() {}

    public var body: some View {
        NavigationSplitView {
            NavigationSidebar()
        } content: {
            SkillListView()
        } detail: {
            SkillDetailView()
        }
        .navigationSplitViewStyle(.balanced)
    }
}

// MARK: Color 语义（红/琥珀/绿/蓝/灰）

private extension String {
    var semanticColor: Color {
        switch self {
        case "green": .green
        case "amber": Color(red: 0.95, green: 0.7, blue: 0.2)
        case "red": .red
        case "blue": .blue
        case "gray": Color(nsColor: .systemGray)
        default: Color(nsColor: .systemGray)
        }
    }
}

// MARK: - 侧栏（导航树）

struct NavigationSidebar: View {
    @Environment(AppEnvironment.self) private var env

    public var body: some View {
        // 导航视图：全侧栏单选（原生高亮），列表 = 选中节点 ∩ 搜索词。
        let l = env.l10n
        return List(selection: Binding(
            get: { env.selectedNode },
            set: { env.select(node: $0) }
        )) {
            Section {
                // 「所有 Skills」根节点：选中态永远有落点（spec：显式默认视图）
                HStack {
                    Image(systemName: "square.grid.2x2")
                        .foregroundStyle(.secondary)
                    Text(l.sidebarAllSkills)
                    Spacer()
                    Text("\(env.catalogStore.current.count)")
                        .foregroundStyle(.secondary)
                        .font(.callout.monospacedDigit())
                }
                .tag(SidebarNode.all)
            }
            Section(l.sectionAgents) {
                // 只显示本机实际安装过的 agent；未安装的 harness 不进侧栏。
                // 行模型由 env memoize（catalog version 键控）——body 不再逐帧重算。
                let rows = env.sidebarRows()
                if rows.isEmpty {
                    Text(l.sidebarNoAgents)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(rows) { row in
                        HStack(spacing: 8) {
                            Image(
                                systemName: row.status == .available
                                    ? "externaldrive.badge.checkmark" : "externaldrive.badge.exclamationmark"
                            )
                            .foregroundStyle(
                                row.status == .available ? Color.green : Color.orange
                            )
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.name)
                                Text(l.agentRowStatus(available: row.status == .available, skillCount: row.skillCount))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(row.skillCount)")
                                .foregroundStyle(.secondary)
                                .font(.callout.monospacedDigit())
                        }
                        .tag(SidebarNode.agent(row.id))
                    }
                }
            }
            Section(l.sectionScopes) {
                ForEach(sections) { section in
                    HStack {
                        Image(systemName: sectionIcon(section.kind))
                            .foregroundStyle(.secondary)
                        Text(section.kind == .global ? l.scopeGlobal : section.title)
                        Spacer()
                        Text("\(section.count)")
                            .foregroundStyle(.secondary)
                            .font(.callout.monospacedDigit())
                    }
                    .tag(section.kind == .global ? SidebarNode.global : .project(section.title))
                }
            }
            tagSectionsSection
            Section(l.sectionLifecycle) {
                ForEach(LifecycleZone.allCases, id: \.self) { zone in
                    let rows = zone == .disabled ? env.disabledZoneRows() : env.trashedZoneRows()
                    HStack {
                        Image(systemName: zone.symbol)
                            .foregroundStyle(.secondary)
                        Text(ZoneListModel.zoneTitle(zone: zone, rows: rows, l10n: l))
                        Spacer()
                        Text("\(rows.count)")
                            .foregroundStyle(.secondary)
                            .font(.callout.monospacedDigit())
                    }
                    .tag(SidebarNode.zone(zone))
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 340)
        .navigationTitle("AgentKeeper")
        .overlay(alignment: .bottom) {
            ScanStatusStrip(scan: env.store.state.scan, skillsCount: env.catalogStore.current.count, l10n: env.l10n)
                .padding(.bottom, 8)
        }
        .animation(motion.animation(for: .listTransition), value: env.store.state.agents.count)
        // 节点失效归一：catalog/agent 变化后，背后集合消失的节点回落「所有 Skills」
        .task { normalizeSelection() }
        .onChange(of: env.catalogStore.version) { _, _ in normalizeSelection() }
        .onChange(of: env.store.state.agents.count) { _, _ in normalizeSelection() }
    }

    private var sections: [NavigationSection] {
        NavigationModel.buildSections(skills: env.catalogStore.current)
    }

    /// 「标签」节（spec 4.x：导航树按标签分组浏览）。
    @ViewBuilder
    private var tagSectionsSection: some View {
        let tagSections = NavigationModel.buildTagSections(
            skills: env.catalogStore.current,
            tagsBySkill: env.tagsBySkill()
        )
        if !tagSections.isEmpty {
            Section(env.l10n.sectionTags) {
                ForEach(tagSections) { section in
                    HStack {
                        Image(systemName: "tag")
                            .foregroundStyle(.secondary)
                        Text(section.title)
                        Spacer()
                        Text("\(section.count)")
                            .foregroundStyle(.secondary)
                            .font(.callout.monospacedDigit())
                    }
                    .tag(SidebarNode.tag(section.title))
                }
            }
        }
    }

    /// 节点失效归一（纯函数在 AppCore）：按标识匹配回落 .all，保持选中稳定。
    private func normalizeSelection() {
        let tagSections = NavigationModel.buildTagSections(
            skills: env.catalogStore.current,
            tagsBySkill: env.tagsBySkill()
        )
        let normalized = NavigationModel.normalize(
            node: env.selectedNode,
            sections: NavigationModel.buildSections(skills: env.catalogStore.current),
            tagTitles: tagSections.map(\.title),
            installedAgentIDs: env.sidebarRows().map(\.id)
        )
        env.select(node: normalized)
    }

    private var motion: MotionPolicy {
        MotionPolicy(reduceMotion: env.motionPolicy.reduceMotion)
    }

    private func sectionIcon(_ kind: NavigationSectionKind) -> String {
        switch kind {
        case .global: "globe.2"
        case .agent: "person.crop.square"
        case .project: "folder"
        case .tag: "tag"
        }
    }
}

// MARK: - 状态条（非阻断）

/// 状态条文案构建（纯函数可测）：完成态必须带时间戳与 skill 数——
/// 手动扫描前后状态一致时，用户仍能看到「本次扫描刚刚完成」的可见反馈。
@MainActor
enum ScanStatusText {
    private static let clock = DateFormatter()
    private static let compactClock = DateFormatter()

    static func clockText(_ date: Date) -> String {
        clock.dateFormat = "HH:mm:ss"
        return clock.string(from: date)
    }

    static func build(scan: ScanPhaseState, skillsCount: Int, l10n: L10n) -> String {
        switch scan.phase {
        case .idle: return l10n.stripIdle
        case .running: return l10n.stripRunning
        case .complete:
            let time = scan.lastCompletedAt.map { clockText($0) } ?? "--:--:--"
            return l10n.stripDone(agents: scan.agentCount, skills: skillsCount, time: time)
        case .failed: return l10n.stripFailedDetail(scan.failureMessage ?? "--")
        }
    }

    /// 紧凑版（窄侧栏防换行）：保留 skill 数与时分，舍弃秒与 agent 数。
    static func compact(scan: ScanPhaseState, skillsCount: Int, l10n: L10n) -> String {
        switch scan.phase {
        case .idle: return l10n.stripIdle
        case .running: return l10n.stripRunningCompact
        case .complete:
            compactClock.dateFormat = "HH:mm"
            let time = scan.lastCompletedAt.map { compactClock.string(from: $0) } ?? "--:--"
            return "\(skillsCount) skills · \(time)"
        case .failed: return l10n.stripFailed
        }
    }
}

struct ScanStatusStrip: View {
    let scan: ScanPhaseState
    let skillsCount: Int
    var l10n: L10n = L10n(lang: .zhHans)
    @Environment(\.openWindow) private var openWindow

    public var body: some View {
        // 窄侧栏（min 200pt）防换行：优先全文案，放不下用紧凑版；单行硬保证
        ViewThatFits(in: .horizontal) {
            label(text: ScanStatusText.build(scan: scan, skillsCount: skillsCount, l10n: l10n))
            label(text: ScanStatusText.compact(scan: scan, skillsCount: skillsCount, l10n: l10n))
        }
        .help(l10n.stripTapOpenMain)
        .onTapGesture {
            // 点击 → 前置主窗口（Skill 列表随 RootView 常驻）
            NSApplication.shared.activate(ignoringOtherApps: true)
            openWindow(id: "main")
        }
        .onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }

    private func label(text: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(tint.colorKey.semanticColor)
                .frame(width: 8, height: 8)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.thinMaterial, in: Capsule())
    }

    private var tint: StatusSemantics {
        // explanation 不直接展示（文案走 ScanStatusText）；仅取色与符号
        switch scan.phase {
        case .idle: StatusSemantics(colorKey: "gray", symbol: "circle", explanation: l10n.stripIdle)
        case .running: StatusSemantics(colorKey: "blue", symbol: "dot.radiowaves.left.and.right", explanation: l10n.stripRunning)
        case .complete: StatusSemantics(colorKey: "green", symbol: "checkmark.circle", explanation: l10n.stripIdle)
        case .failed: StatusSemantics(colorKey: "red", symbol: "xmark.circle", explanation: l10n.stripFailed)
        }
    }
}

/// Skill 列表行内容（不含 List 容器：离屏快照可经 VStack 引用真实行像素）。
struct SkillRowView: View {
    let skill: Skill
    var l10n: L10n = L10n(lang: .zhHans)

    var body: some View {
        HStack(spacing: 8) {
            let status = token(of: skill)
            let semantics = StatusSemantics.resolve(status)
            Image(systemName: semantics.symbol)
                .foregroundStyle(semantics.colorKey.semanticColor)
                .help(statusHelp(status))
            VStack(alignment: .leading, spacing: 2) {
                Text(skill.name).font(.body)
                Text(subtitle(skill))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if !skill.issues.isEmpty {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                    .font(.caption)
                    .help(l10n.healthBadgeHelp)
            }
            Text(l10n.scopeBadge(skill.scope))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(.quaternary.opacity(0.5)))
        }
    }

    private func token(of skill: Skill) -> StatusToken {
        if skill.status == .disabled { return .disabled }
        return .enabled
    }

    private func statusHelp(_ token: StatusToken) -> String {
        switch token {
        case .disabled: l10n.statusDisabledHelp
        case .unrecognized: l10n.statusUnrecognizedHelp
        case .permissionDenied: l10n.permissionDeniedHelp
        case .enabled, .changed, .conflict: l10n.statusEnabledHelp
        }
    }

    private func subtitle(_ skill: Skill) -> String {
        var parts: [String] = []
        // 全局/同铺设 skill 拥有多个 owner——只显示第一个会誤导（看似专属）
        let owners = skill.owners.joined(separator: "、")
        if !owners.isEmpty { parts.append(owners) }
        if let desc = skill.skillDescription, !desc.isEmpty { parts.append(desc) }
        return parts.joined(separator: " · ")
    }
}

// MARK: - 列表（筛选/搜索）

struct SkillListView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var showGitInstall = false
    @State private var importError: String?

    public var body: some View {
        @Bindable var env = env
        // 生命周期区节点：列表位切换为区视图（同属单选导航，无组合语义）
        if case let .zone(zone) = env.selectedNode {
            ZoneListView(zone: zone)
                .navigationTitle(NavigationModel.listTitle(for: env.selectedNode, l10n: env.l10n))
        } else {
            // 筛选结果本帧只算一次：animation value 与列表使用同一份（曾每帧/每击键跑两条全量管线）
            let query = SkillListCore.filter(env.searchText, env)
            listCore(query)
                .searchable(text: $env.searchText, placement: .automatic, prompt: Text(env.l10n.searchPrompt))
                .navigationTitle(NavigationModel.listTitle(for: env.selectedNode, l10n: env.l10n))
                .toolbar { toolbarContent }
                .sheet(isPresented: $showGitInstall) {
                    GitInstallSheet()
                }
                .alert(env.l10n.importFailed, isPresented: Binding(
                    get: { importError != nil },
                    set: { if !$0 { importError = nil } }
                )) {
                    Button(env.l10n.importButtonOK, role: .cancel) { }
                } message: {
                    Text(importError ?? "")
                }
                .animation(motion.animation(for: .listTransition), value: query.map({ $0.id }))
        }
    }

    /// 列表核心（独立节点视图：body 内使用 @Environment 的部分收敛于此，selection binding
    /// 在求值期捕获具体 env 对象，避免捕获未解析的 Environment 包装器——离屏渲染也不会崩）。
    func listCore(_ query: [Skill]) -> some View {
        SkillListCore(query: query)
    }


    // MARK: 工具条

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        let l = env.l10n
        ToolbarItemGroup {
            Button {
                Task { await env.scanNow() }
            } label: {
                // 运行中就地显示进度（与菜单栏一致）——否则手动扫描期间按钮无任何可感反馈
                if env.store.state.scan.phase == .running {
                    HStack(spacing: 4) {
                        ProgressView().controlSize(.small)
                        Text(l.scanning)
                    }
                } else {
                    Label(l.scanNow, systemImage: "arrow.clockwise")
                }
            }
            .disabled(env.store.state.scan.phase == .running)
            Button {
                Task { await importFromPanel() }
            } label: {
                Label(l.importSkill, systemImage: "square.and.arrow.down")
            }
            Button {
                showGitInstall = true
            } label: {
                Label(l.installFromGit, systemImage: "arrow.down.circle")
            }
            // 设置（⌘,）：macOS 官方 SettingsLink 打开 Settings 场景窗口
            SettingsLink {
                Label(l.settingsMenu, systemImage: "gearshape")
            }
        }
    }

    /// 本地目录导入（NSOpenPanel；失败走 alert 非阻断呈现）。
    private func importFromPanel() async {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = env.l10n.commonInstall
        panel.message = env.l10n.gitSheetTitle
        let response = panel.runModal()
        guard response == .OK, let directory = panel.url else { return }
        let targetRoot = currentTargetRoot()
        guard let targetRoot else {
            importError = env.l10n.importNoTargetRoots
            return
        }
        await env.importSkill(from: directory, targetSkillRoot: targetRoot)
        if let message = env.store.state.operation.failureMessage {
            importError = message
        }
    }

    /// 导入目标 skill 根默认值：第一个已安装 agent 的第一个用户级 skill 根。
    private func currentTargetRoot() -> URL? {
        let installed = env.store.state.agents
        for agent in installed {
            if let root = agent.skillRoots.first {
                return root.path
            }
        }
        return nil
    }

    private var motion: MotionPolicy { env.motionPolicy }}

struct SkillListCore: View {
    @Environment(AppEnvironment.self) private var env
    /// 父级（SkillListView）本帧已算好的筛选结果——不再重复全量管线。
    let query: [Skill]

    var body: some View {
        // 捕获已解析的具体 env 对象（%@Environment 包装器在离屏/闭包拷贝中不可靠）
        let env = self.env
        let l = env.l10n
        return List(selection: Binding(
            get: { env.selectedSkillID },
            set: { env.selectedSkillID = $0 }
        )) {
            ForEach(query) { skill in
                SkillRowView(skill: skill, l10n: l)
                    .transition(.opacity)
            }
        }
        .overlay {
            if query.isEmpty {
                ContentUnavailableView(
                    l.noMatchingSkills,
                    systemImage: "magnifyingglass",
                    description: Text(l.adjustFilterOrRescan)
                )
            }
        }
    }

    // MARK: 数据

    /// 筛选逻辑（static：父级 animation 亦需同一结果）。
    /// 组合语义唯一收口：侧栏节点（NavigationModel.catalogQuery）∩ 搜索词。
    static func filter(_ searchText: String, _ env: AppEnvironment) -> [Skill] {
        guard var query = NavigationModel.catalogQuery(for: env.selectedNode) else { return [] }
        query.searchText = searchText
        // 标签节点需要合成禁用条目；普通视图只见可用 catalog
        let isTagNode: Bool = { if case .tag = env.selectedNode { return true }; return false }()
        let catalog = isTagNode ? env.catalogForTagFilter() : env.catalogStore.current
        // 无标签筛选时不取标签映射（曾每次 filter 都做 N 次串行队列锁往返）
        let tags = isTagNode ? env.tagsBySkill() : [:]
        return query.apply(catalog: catalog, tagsBySkill: tags)
    }
}

// MARK: - 详情面板

struct SkillDetailView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var pendingError: String?
    @State private var newTagText = ""
    @State private var showInstallSheet = false
    @State private var confirmUpdateAll = false

    public var body: some View {
        if let skill = selectedSkill {
            ScrollView {
                SkillDetailContent(
                    env: env,
                    skill: skill,
                    showInstallSheet: $showInstallSheet,
                    confirmUpdateAll: $confirmUpdateAll
                )
                .padding(24)
            }
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .transition(.opacity)
            .sheet(isPresented: $showInstallSheet) {
                InstallToAgentSheet(skill: skill)
            }
            .confirmationDialog(
                env.l10n.updateAllTitle,
                isPresented: $confirmUpdateAll,
                titleVisibility: .visible
            ) {
                Button(env.l10n.updateAllButton) {
                    Task { _ = await env.updateAllLandingPoints(from: skill) }
                }
                Button(env.l10n.commonCancel, role: .cancel) { }
            } message: {
                Text(env.l10n.updateAllMessage)
            }
        } else {
            // MangoDisk 式：未选中时展示扫描产出总览（统计/分布/agent 卡片）
            OverviewDashboard()
        }
    }

    private var selectedSkill: Skill? {
        guard let id = env.selectedSkillID else { return nil }
        return env.catalogStore.current.first { $0.id == id }
    }

    private var motion: MotionPolicy { env.motionPolicy }

}


/// Skill 详情正文（不含 ScrollView：离屏快照可独立渲染；env 显式注入而非 @Environment）。
@MainActor
struct SkillDetailContent: View {
    let env: AppEnvironment
    let skill: Skill
    @Binding var showInstallSheet: Bool
    @Binding var confirmUpdateAll: Bool
    @State private var newTagText = ""
    // 预览数据异步加载（task(id:) 切换 skill 时先清空 → 加载效果，I/O 不占主线程）
    @State private var markdown: String?
    @State private var files: [SkillPreviewModel.FileListEntry]?
    // history/snapshots 同法异步（曾每次 body 求值同步读盘/遍历 manifest——
    // 列表滚动 + 面板渲染的次级卡顿源）
    @State private var historyRecords: [OperationRecord]?
    @State private var snapshotsList: [SnapshotMetadata]?

    var body: some View {
        SwiftUI.Group {
            VStack(alignment: .leading, spacing: 16) {
                header(skill)
                scopeBadge(skill)
                SkillEffectSection(skill: skill, l10n: env.l10n)
                SkillHealthSection(skill: skill, l10n: env.l10n)
                tagsSection(skill)
                landingPointsSection(skill)
                Divider()
                previewSection(skill)
                Divider()
                filesSection(skill)
                Divider()
                historySection(skill)
                snapshotsSection(skill)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: skill.id) {
            // 切换 skill：立即清空旧数据（避免停留在上一个），再后台并行加载
            markdown = nil
            files = nil
            historyRecords = nil
            snapshotsList = nil
            async let md = SkillPreviewModel.loadMarkdown(skillDir: skill.directory)
            async let fs = SkillPreviewModel.loadFiles(skillDir: skill.directory)
            // 空串哨兵 = SKILL.md 缺失（nil = 加载中；占位文案按语言渲染）
            (markdown, files) = await (md ?? "", fs)
            // 历史/快照走各自的读区（快照要枚举快照目录 manifest）；store 均 @unchecked Sendable
            let historyStore = env.history
            let snapshotStore = env.snapshots
            let recentLimit = Self.envLimit
            let loadedHistory: [OperationRecord] = await Task.detached(priority: .utility) { [name = skill.name] in
                historyStore.recent(limit: recentLimit).filter { $0.name == name }
            }.value
            let loadedSnapshots: [SnapshotMetadata] = await Task.detached(priority: .utility) { [skillID = skill.id] in
                snapshotStore.snapshots(skillID: skillID)
            }.value
            historyRecords = loadedHistory
            snapshotsList = loadedSnapshots
        }
    }

    private static let envLimit = 8

// MARK: 区块

    // MARK: 区块

    private func header(_ skill: Skill) -> some View {
        HStack(alignment: .top, spacing: 12) {
            let semantics = StatusSemantics.resolve(skill.status == .disabled ? .disabled : .enabled)
            Image(systemName: semantics.symbol)
                .font(.system(size: 28))
                .foregroundStyle(semantics.colorKey.semanticColor)
                .help(semantics.explanation)
            VStack(alignment: .leading, spacing: 4) {
                Text(skill.name).font(.title2).bold()
                if let desc = skill.skillDescription, !desc.isEmpty {
                    Text(desc).font(.callout).foregroundStyle(.secondary)
                }
                Text(skill.directory.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }
            Spacer()
        }
    }

    private func scopeBadge(_ skill: Skill) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Label(scopeText(skill), systemImage: "scope")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(.quaternary.opacity(0.5)))
                Spacer()
                operationButtons(skill)
            }
            Text("sha256 \(String(skill.sha256.prefix(12)))…")
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func operationButtons(_ skill: Skill) -> some View {
        let isDisabled = skill.status == .disabled
        let pending = env.store.state.operation
        let l = env.l10n
        Button {
            Task { await env.runOperation(skill: skill, direction: isDisabled ? .enable : .disable) }
        } label: {
            Label(isDisabled ? l.opEnable : l.opDisable, systemImage: isDisabled ? "checkmark.circle" : "pause.circle")
        }
        .disabled(pending.inFlight != nil)
        .help(pending.failureMessage ?? (isDisabled ? l.enableHelp : l.disableHelp))
        if !isDisabled {
            Button {
                showInstallSheet = true
            } label: {
                Label(l.opInstallToAgents, systemImage: "arrow.up.circle")
            }
            .disabled(pending.inFlight != nil)
            .help(l.installToAgentsHelp)
            // 删除 = 移入回收站（原样保全可回滚；彻底删除走回收站二次确认）
            Button(role: .destructive) {
                Task { await env.runOperation(skill: skill, direction: .delete) }
            } label: {
                Label(l.opMoveToTrash, systemImage: "trash")
            }
            .disabled(pending.inFlight != nil)
            .help(l.moveToTrashHelp)
        }
    }

    // MARK: - Phase 2 区块

    /// 标签 chips（增删；spec：自定义标签 workset）。
    private func tagsSection(_ skill: Skill) -> some View {
        let current = env.tagService.tags(forSkillID: skill.id)
        return VStack(alignment: .leading, spacing: 8) {
            Label(env.l10n.detailTags, systemImage: "tag")
                .font(.headline)
            if !current.isEmpty {
                FlowChips(tags: current, onRemove: { tag in
                    env.tagService.removeTag(tag, fromSkillID: skill.id)
                }, removeHelp: env.l10n.removeTagHelp)
            }
            HStack {
                TextField(env.l10n.detailNewTagPrompt, text: $newTagText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 240)
                Button(env.l10n.commonAdd) {
                    let name = newTagText.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { return }
                    env.tagService.addTag(name, toSkillID: skill.id)
                    newTagText = ""
                }
                .disabled(newTagText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    /// 同名安装面板（spec 4.x：各 agent 副本互查 / 分歧提示 / 一键用当前版本更新全部副本）。
    /// 指纹比对用 catalog 已缓存的 sha256（零磁盘 IO）——目录树哈希曾写在 body 里，
    /// 每次视图求值对每个落点做全树读盘+SHA256，是详情面板顿挫的最大单点。
    private func landingPointsSection(_ skill: Skill) -> some View {
        let catalog = env.catalogStore.current
        let points = CatalogQuery.namedLandingPoints(named: skill.name, catalog: catalog)
        let diverged = CatalogQuery.isDiverged(name: skill.name, catalog: catalog)
        // 落点目录 → 该目录对应 skill 的指纹（同名 skill 与落点目录一一对应）
        let shaByPath: [String: String] = Dictionary(
            uniqueKeysWithValues: catalog
                .filter { $0.name == skill.name }
                .map { ($0.directory.standardizedFileURL.path, $0.sha256) }
        )
        return Group {
            if points.count > 1 || diverged {
                VStack(alignment: .leading, spacing: 8) {
                    Label(
                        diverged ? env.l10n.landingDiverged : env.l10n.landingSameName,
                        systemImage: diverged ? "exclamationmark.triangle" : "link"
                    )
                    .font(.headline)
                    .foregroundStyle(diverged ? Color.orange : .primary)
                    ForEach(Array(points.enumerated()), id: \.element.directory.standardizedFileURL.path) { entry in
                        let point = entry.element
                        let pointSha = shaByPath[point.directory.standardizedFileURL.path]
                        let matches = pointSha == skill.sha256
                        HStack(spacing: 6) {
                            Image(
                                systemName: matches
                                    ? "checkmark.circle" : "exclamationmark.triangle"
                            )
                            .foregroundStyle(
                                matches ? Color.green : Color.orange
                            )
                            Text(point.agentID).font(.callout)
                            Text(point.directory.path)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    HStack {
                        Button(env.l10n.landingUpdateAll) {
                            confirmUpdateAll = true
                        }
                        .disabled(env.store.state.operation.inFlight != nil)
                    }
                }
            }
        }
    }

    private var motion: MotionPolicy { env.motionPolicy }

    @ViewBuilder
    private func previewSection(_ skill: Skill) -> some View {
        if let markdown, !markdown.isEmpty {
            // 块级 markdown 渲染器：标题层级/代码块/列表/引用 + 可折叠 + 卡内滚动
            MarkdownDocumentView(markdown: markdown, motion: motion, l10n: env.l10n)
        } else if markdown != nil {
            // SKILL.md 缺失/为空（空串哨兵）
            Text(env.l10n.markdownMissing)
                .font(.body)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Label(env.l10n.detailPreview, systemImage: "doc.text")
                    .font(.headline)
                loadingPlaceholder(env.l10n.detailReadingSkillMd)
            }
        }
    }

    @ViewBuilder
    private func filesSection(_ skill: Skill) -> some View {
        if let files {
            // Finder 风格：图标/缩进/点选；双击或菜单在 Finder 中定位
            FileListView(baseDirectory: skill.directory, entries: files, l10n: env.l10n)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Label(env.l10n.detailFiles, systemImage: "doc.on.doc")
                    .font(.headline)
                loadingPlaceholder(env.l10n.detailListingFiles)
            }
        }
    }

    /// 异步加载中的占位（切换 skill 的加载效果）。
    private func loadingPlaceholder(_ text: String) -> some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(text)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
    }

    private func historySection(_ skill: Skill) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(env.l10n.detailHistory, systemImage: "clock.arrow.circlepath")
                .font(.headline)
            // 异步加载中占位；历史记录随操作刷新（runOperation 后重扫触发 task(id:) 重载）
            let records = historyRecords ?? []
            if records.isEmpty {
                Text(historyRecords == nil ? env.l10n.commonLoading : env.l10n.detailNoHistory)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(records, id: \.performedAt) { record in
                    HStack {
                        Image(systemName: resultIcon(record.result))
                            .foregroundStyle(resultTint(record.result).semanticColor)
                        Text(directionText(record.direction))
                        if case let .failure(message) = record.result {
                            Text(message)
                                .font(.caption2)
                                .foregroundStyle(.red)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text(record.performedAt, style: .time)
                            .foregroundStyle(.tertiary)
                            .font(.caption)
                    }
                    .font(.caption)
                }
            }
        }
    }

    private func snapshotsSection(_ skill: Skill) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(env.l10n.detailSnapshots, systemImage: "camera.on.rectangle")
                .font(.headline)
            // 异步加载中占位（曾每次 body 求值同步枚举快照 manifest 全表）
            let snapshots = snapshotsList ?? []
            if snapshots.isEmpty {
                Text(snapshotsList == nil ? env.l10n.commonLoading : env.l10n.detailNoSnapshots)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(Array(snapshots.enumerated()), id: \.element.sha) { index, snapshot in
                    Button {
                        Task { await env.restoreSnapshot(skill: skill, sha: snapshot.sha) }
                    } label: {
                        HStack {
                            Text("#\(snapshots.count - index)")
                            Text(snapshot.capturedAt, style: .date)
                            Spacer()
                            Image(systemName: "arrow.counterclockwise")
                        }
                        .font(.caption)
                    }
                    .buttonStyle(.link)
                    .help(env.l10n.restoreSnapshotHelp(snapshots.count - index))
                }
            }
        }
    }

    // MARK: 辅助

    private func scopeText(_ skill: Skill) -> String {
        env.l10n.scopeDetailText(skill.scope)
    }

    private func directionText(_ direction: OperationDirection) -> String {
        switch direction {
        case .disable: env.l10n.dirDisable
        case .enable: env.l10n.dirEnable
        case .snapshotRestore: env.l10n.dirSnapshotRestore
        case .delete: env.l10n.dirDelete
        case .distribute: env.l10n.dirDistribute
        case .updateLandingPoints: env.l10n.dirUpdateAll
        }
    }

    private func resultIcon(_ result: OperationResult) -> String {
        if result == .success { return "checkmark.seal" }
        return "exclamationmark.bubble"
    }

    private func resultTint(_ result: OperationResult) -> String {
        if result == .success { return "green" }
        return "red"
    }
}

// MARK: - Phase 2 视图组件

/// 标签 chips 布局（可删除），自动流式换行。
struct FlowChips: View {
    let tags: [String]
    let onRemove: (String) -> Void
    var removeHelp: String = "移除标签"

    /// 简化双列流式布局：标签量级小（个人 workset），取自然折行即可。
    public var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 110), alignment: .leading)],
            alignment: .leading,
            spacing: 6
        ) {
            ForEach(tags, id: \.self) { tag in
                HStack(spacing: 4) {
                    Image(systemName: "tag")
                        .font(.caption2)
                    Text(tag).font(.caption)
                    Button {
                        onRemove(tag)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(removeHelp)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill(Color.accentColor.opacity(0.12))
                )
            }
        }
    }
}

/// 「安装到其他 agent…」面板（spec：跨 agent 非破坏安装 + 冲突不覆盖）。
struct InstallToAgentSheet: View {
    let skill: Skill
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var selection: AgentTarget?

    private struct AgentTarget: Identifiable, Hashable {
        let agentID: AgentID
        let root: URL
        var id: String { agentID + ":" + root.path }
    }

    public var body: some View {
        let l = env.l10n
        VStack(alignment: .leading, spacing: 16) {
            Label(l.installSheetTitle(skill.name), systemImage: "arrow.up.circle")
                .font(.headline)
            Text(l.installSheetExplain)
                .font(.caption)
                .foregroundStyle(.secondary)

            let targets = availableTargets
            if targets.isEmpty {
                ContentUnavailableView(
                    l.installNoTargets,
                    systemImage: "tray",
                    description: Text(l.installNoTargetsDetail)
                )
            } else {
                List(selection: Binding(
                    get: { selection },
                    set: { selection = $0 }
                )) {
                    ForEach(targets) { target in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(target.agentID).font(.body)
                                Text(target.root.path)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                            if selection == target {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { selection = target }
                    }
                }
                .frame(minHeight: 180)
            }

            HStack {
                Spacer()
                Button(l.commonCancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(l.commonInstall) {
                    guard let selection else { return }
                    Task {
                        await env.distributeInstall(skill: skill, targetSkillRoot: selection.root)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selection == nil)
            }
        }
        .padding(20)
        .frame(width: 480, height: 380)
    }

    /// 可选目标：全部已安装 agent 的 skill 根（排除 skill 当前所在的根，防自我复制）。
    private var availableTargets: [AgentTarget] {
        let currentPath = skill.directory.standardizedFileURL.path
        return env.store.state.agents.flatMap { agent in
            agent.skillRoots.map { root in
                AgentTarget(agentID: agent.id, root: root.path)
            }
        }.filter { $0.root.standardizedFileURL.path != currentPath }
    }
}

/// 「从 git 安装…」面板（spec：URL 输入 → 候选勾选 → 安装；失败如实展示）。
struct GitInstallSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var urlText = ""
    @State private var candidates: [GitSkillCandidate] = []
    @State private var selected: Set<String> = []
    @State private var proposalStage = false
    @State private var proposing = false
    @State private var targetRoot: URL?

    public var body: some View {
        let l = env.l10n
        VStack(alignment: .leading, spacing: 16) {
            Label(l.gitSheetTitle, systemImage: "arrow.down.circle")
                .font(.headline)
            HStack {
                TextField(l.gitURLPlaceholder, text: $urlText)
                    .textFieldStyle(.roundedBorder)
                Button(l.gitFindCandidates) {
                    Task { await propose() }
                }
                .disabled(urlText.trimmingCharacters(in: .whitespaces).isEmpty || proposing)
            }

            if proposing {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(l.gitCloning).foregroundStyle(.secondary)
                }
            }

            if proposalStage {
                if candidates.isEmpty {
                    Text(l.gitNoSkills)
                        .foregroundStyle(.secondary)
                } else {
                    Text(l.gitPickSkills).font(.callout)
                    List(candidates) { candidate in
                        HStack {
                            Toggle(candidate.name, isOn: Binding(
                                get: { selected.contains(candidate.name) },
                                set: { on in
                                    if on { selected.insert(candidate.name) } else { selected.remove(candidate.name) }
                                }
                            ))
                            Spacer()
                            Text(candidate.directory.path)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .frame(minHeight: 160)

                    Picker(l.gitInstallTo, selection: $targetRoot) {
                        ForEach(targetChoices, id: \.self) { root in
                            Text(root.path).tag(root as URL?)
                        }
                    }
                    .frame(maxWidth: 360)
                }
            }

            HStack {
                Spacer()
                Button(l.commonCancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(l.commonInstall) {
                    Task { await install() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(candidates.isEmpty || selected.isEmpty || targetRoot == nil)
            }
        }
        .padding(20)
        .frame(width: 560, height: 440)
        .onAppear {
            targetRoot = defaultTarget()
        }
    }

    private var targetChoices: [URL] {
        env.store.state.agents.flatMap { agent in
            agent.skillRoots.map(\.path)
        }
    }

    private func defaultTarget() -> URL? {
        targetChoices.first
    }

    private func propose() async {
        proposing = true
        candidates = []
        selected = []
        let url = urlText.trimmingCharacters(in: .whitespaces)
        let found = await env.proposeGitCandidates(url: url)
        proposing = false
        proposalStage = true
        candidates = found
        selected = Set(found.map(\.name))
    }

    private func install() async {
        guard let targetRoot else { return }
        let picked = candidates.filter { selected.contains($0.name) }
        await env.installGitCandidates(picked, targetSkillRoot: targetRoot)
        dismiss()
    }
}
