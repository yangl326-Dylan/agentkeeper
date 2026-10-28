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
        List {
            Section("Agents") {
                ForEach(env.store.state.agents) { agent in
                    Label(
                        agentLabel(agent),
                        systemImage: agentIcon(agent)
                    )
                    .foregroundStyle(
                        StatusSemantics.resolve(
                            agentStatusToken(agent)
                        ).colorKey.semanticColor
                    )
                }
            }
            Section("Skills") {
                ForEach(sections) { section in
                    Button {
                        env.selectedTag = nil
                    } label: {
                        HStack {
                            Image(systemName: sectionIcon(section.kind))
                                .foregroundStyle(.secondary)
                            Text(section.title)
                            Spacer()
                            Text("\(section.count)")
                                .foregroundStyle(.secondary)
                                .font(.callout.monospacedDigit())
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            tagSectionsSection
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 340)
        .navigationTitle("AgentKeeper")
        .overlay(alignment: .bottom) {
            ScanStatusStrip(scan: env.store.state.scan)
                .padding(.bottom, 8)
        }
        .animation(motion.animation(for: .listTransition), value: env.store.state.agents.count)
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
            Section("标签") {
                ForEach(tagSections) { section in
                    Button {
                        env.selectedTag = section.title
                    } label: {
                        HStack {
                            Image(systemName: "tag")
                                .foregroundStyle(.secondary)
                            Text(section.title)
                            Spacer()
                            Text("\(section.count)")
                                .foregroundStyle(.secondary)
                                .font(.callout.monospacedDigit())
                            if env.selectedTag == section.title {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var motion: MotionPolicy {
        MotionPolicy(reduceMotion: env.motionPolicy.reduceMotion)
    }

    private func agentLabel(_ agent: Agent) -> String {
        if case .unrecognizedStructure = agent.installState {
            return agent.name + "（结构未知）"
        }
        return agent.name
    }

    private func agentIcon(_ agent: Agent) -> String {
        if case .installed = agent.installState { return "externaldrive.badge.checkmark" }
        return "externaldrive.badge.exclamationmark"
    }

    private func agentStatusToken(_ agent: Agent) -> StatusToken {
        if case .unrecognizedStructure = agent.installState { return .unrecognized }
        return .enabled
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

struct ScanStatusStrip: View {
    let scan: ScanPhaseState

    public var body: some View {
        HStack(spacing: 6) {
            Circle().fill(tint.colorKey.semanticColor)
                .frame(width: 8, height: 8)
            Text(text).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.thinMaterial, in: Capsule())
    }

    private var tint: StatusSemantics {
        switch scan.phase {
        case .idle: StatusSemantics(colorKey: "gray", symbol: "circle", explanation: "空闲")
        case .running: StatusSemantics(colorKey: "blue", symbol: "dot.radiowaves.left.and.right", explanation: "扫描中")
        case .complete: StatusSemantics(colorKey: "green", symbol: "checkmark.circle", explanation: "完成")
        case .failed: StatusSemantics(colorKey: "red", symbol: "xmark.circle", explanation: "失败")
        }
    }

    private var text: String {
        switch scan.phase {
        case .idle: "空闲"
        case .running: "正在扫描…"
        case .complete: "完成 · \(scan.agentCount) agents · \(scan.diagnosticCount) 诊断"
        case .failed: "扫描失败：\(scan.failureMessage ?? "未知")"
        }
    }
}

/// Skill 列表行内容（不含 List 容器：离屏快照可经 VStack 引用真实行像素）。
struct SkillRowView: View {
    let skill: Skill

    var body: some View {
        HStack(spacing: 8) {
            let semantics = StatusSemantics.resolve(token(of: skill))
            Image(systemName: semantics.symbol)
                .foregroundStyle(semantics.colorKey.semanticColor)
                .help(semantics.explanation)
            VStack(alignment: .leading, spacing: 2) {
                Text(skill.name).font(.body)
                Text(subtitle(skill))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(scopeLabel(skill))
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

    private func subtitle(_ skill: Skill) -> String {
        var parts: [String] = []
        // 全局/同铺设 skill 拥有多个 owner——只显示第一个会誤导（看似专属）
        let owners = skill.owners.joined(separator: "、")
        if !owners.isEmpty { parts.append(owners) }
        if let desc = skill.skillDescription, !desc.isEmpty { parts.append(desc) }
        return parts.joined(separator: " · ")
    }

    private func scopeLabel(_ skill: Skill) -> String {
        switch skill.scope {
        case .global: "全局"
        case .agentOnly: "专属"
        case .project: "项目 \(skill.projectTag() ?? "")"
        case .multiAgent: "同铺设"
        }
    }
}

// MARK: - 列表（筛选/搜索）

struct SkillListView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var searchText = ""
    @State private var scopeFilter: Set<ScopeKind> = []
    @State private var showGitInstall = false
    @State private var importError: String?

    public var body: some View {
        listCore
            .searchable(text: $searchText, placement: .automatic, prompt: "搜索名称 / 描述 / 项目")
            .toolbar { toolbarContent }
            .sheet(isPresented: $showGitInstall) {
                GitInstallSheet()
            }
            .alert("导入失败", isPresented: Binding(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )) {
                Button("好", role: .cancel) { }
            } message: {
                Text(importError ?? "")
            }
            .animation(motion.animation(for: .listTransition), value: SkillListCore.filter(scopeFilter, searchText, env).map({ $0.id }))
    }

    /// 列表核心（独立节点视图：body 内使用 @Environment 的部分收敛于此，selection binding
    /// 在求值期捕获具体 env 对象，避免捕获未解析的 Environment 包装器——离屏渲染也不会崩）。
    var listCore: some View {
        SkillListCore(searchText: $searchText, scopeFilter: $scopeFilter)
    }


    // MARK: 工具条

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            Menu {
                Toggle("全局", isOn: scopeToggle(.global))
                Toggle("Agent 专属", isOn: scopeToggle(.agentOnly))
                Toggle("项目级", isOn: scopeToggle(.project))
                Toggle("同铺设", isOn: scopeToggle(.multiAgent))
                Divider()
                tagFilterMenu
            } label: {
                Label("筛选", systemImage: "line.3.horizontal.decrease.circle")
            }
            Button {
                Task { await env.scanNow() }
            } label: {
                Label("立即扫描", systemImage: "arrow.clockwise")
            }
            .disabled(env.store.state.scan.phase == .running)
            Button {
                Task { await importFromPanel() }
            } label: {
                Label("导入 skill…", systemImage: "square.and.arrow.down")
            }
            Button {
                showGitInstall = true
            } label: {
                Label("从 git 安装…", systemImage: "arrow.down.circle")
            }
        }
    }

    /// 标签筛选子菜单（spec：统一视图按标签筛选，含禁用条目）。
    @ViewBuilder
    private var tagFilterMenu: some View {
        if env.tagService.tags().isEmpty {
            Text("暂无自定义标签").foregroundStyle(.secondary)
        } else {
            Menu("按标签…") {
                Toggle("全部", isOn: Binding(get: { env.selectedTag == nil }, set: { _ in env.selectedTag = nil }))
                ForEach(env.tagService.tags(), id: \.self) { tag in
                    Toggle(tag, isOn: Binding(
                        get: { env.selectedTag == tag },
                        set: { on in env.selectedTag = on ? tag : nil }
                    ))
                }
            }
        }
    }

    /// 本地目录导入（NSOpenPanel；失败走 alert 非阻断呈现）。
    private func importFromPanel() async {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "导入"
        panel.message = "选择包含 SKILL.md 的 skill 目录"
        let response = panel.runModal()
        guard response == .OK, let directory = panel.url else { return }
        let targetRoot = currentTargetRoot()
        guard let targetRoot else {
            importError = "没有可用的 agent skill 目录（先扫描或检查目录结构）"
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

    private func scopeToggle(_ kind: ScopeKind) -> Binding<Bool> {
        Binding(
            get: { scopeFilter.contains(kind) },
            set: { on in
                if on { scopeFilter.insert(kind) } else { scopeFilter.remove(kind) }
            }
        )
    }

    private var motion: MotionPolicy { env.motionPolicy }}

struct SkillListCore: View {
    @Environment(AppEnvironment.self) private var env
    @Binding var searchText: String
    @Binding var scopeFilter: Set<ScopeKind>

    var body: some View {
        // 捕获已解析的具体 env 对象（%@Environment 包装器在离屏/闭包拷贝中不可靠）
        let env = self.env
        let query = filtered()
        return List(selection: Binding(
            get: { env.selectedSkillID },
            set: { env.selectedSkillID = $0 }
        )) {
            ForEach(query) { skill in
                SkillRowView(skill: skill)
                    .transition(.opacity)
            }
        }
        .overlay {
            if query.isEmpty {
                ContentUnavailableView(
                    "没有匹配的 Skill",
                    systemImage: "magnifyingglass",
                    description: Text("调整筛选或重新扫描")
                )
            }
        }
    }

    // MARK: 数据

    /// 筛选逻辑（static：父级 animation 亦需同一结果）。
    static func filter(_ scopeFilter: Set<ScopeKind>, _ searchText: String, _ env: AppEnvironment) -> [Skill] {
        var query = CatalogQuery.initial
        query.scopeKinds = scopeFilter
        query.searchText = searchText
        query.tag = env.selectedTag
        // 标签筛选需要合成禁用条目；普通视图只见可用 catalog
        let catalog = env.selectedTag == nil ? env.catalogStore.current : env.catalogForTagFilter()
        return query.apply(catalog: catalog, tagsBySkill: env.tagsBySkill())
    }

    private func filtered() -> [Skill] {
        Self.filter(scopeFilter, searchText, env)
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
                "以此版本更新所有落点？",
                isPresented: $confirmUpdateAll,
                titleVisibility: .visible
            ) {
                Button("更新（先自动快照各落点）") {
                    Task { _ = await env.updateAllLandingPoints(from: skill) }
                }
                Button("取消", role: .cancel) { }
            } message: {
                Text("即将覆盖同名铺设落点中被修改的版本；每个落点都会先自动保存快照。禁用区条目跳过。")
            }
        } else {
            ContentUnavailableView("选择一个 Skill", systemImage: "square.on.rounded.square")
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

    var body: some View {
        SwiftUI.Group {
            VStack(alignment: .leading, spacing: 16) {
                header(skill)
                scopeBadge(skill)
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
    }

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
        HStack(spacing: 8) {
            Label(scopeText(skill), systemImage: "scope")
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(.quaternary.opacity(0.5)))
            Text("sha256 \(String(skill.sha256.prefix(12)))…")
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)
            Spacer()
            operationButtons(skill)
        }
    }

    @ViewBuilder
    private func operationButtons(_ skill: Skill) -> some View {
        let isDisabled = skill.status == .disabled
        let pending = env.store.state.operation
        Button {
            Task { await env.runOperation(skill: skill, direction: isDisabled ? .enable : .disable) }
        } label: {
            Label(isDisabled ? "恢复启用" : "禁用", systemImage: isDisabled ? "checkmark.circle" : "pause.circle")
        }
        .disabled(pending.inFlight != nil)
        .help(pending.failureMessage ?? (isDisabled ? "按 manifest 回原路径" : "移至统一禁用区"))
        if !isDisabled {
            Button {
                showInstallSheet = true
            } label: {
                Label("安装到其他 agent…", systemImage: "arrow.up.circle")
            }
            .disabled(pending.inFlight != nil)
            .help("复制到其他 agent 的 skill 目录（同名冲突不覆盖）")
        }
    }

    // MARK: - Phase 2 区块

    /// 标签 chips（增删；spec：自定义标签 workset）。
    private func tagsSection(_ skill: Skill) -> some View {
        let current = env.tagService.tags(forSkillID: skill.id)
        return VStack(alignment: .leading, spacing: 8) {
            Label("标签", systemImage: "tag")
                .font(.headline)
            if !current.isEmpty {
                FlowChips(tags: current) { tag in
                    env.tagService.removeTag(tag, fromSkillID: skill.id)
                }
            }
            HStack {
                TextField("新标签名（回车添加）", text: $newTagText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 240)
                Button("添加") {
                    let name = newTagText.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { return }
                    env.tagService.addTag(name, toSkillID: skill.id)
                    newTagText = ""
                }
                .disabled(newTagText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    /// 同名铺设落点面板（spec 4.x：落点互链 / 分歧提示 / 更新所有落点入口）。
    private func landingPointsSection(_ skill: Skill) -> some View {
        let points = CatalogQuery.namedLandingPoints(named: skill.name, catalog: env.catalogStore.current)
        let diverged = CatalogQuery.isDiverged(name: skill.name, catalog: env.catalogStore.current)
        return Group {
            if points.count > 1 || diverged {
                VStack(alignment: .leading, spacing: 8) {
                    Label(
                        diverged ? "同名铺设（已分歧）" : "同名铺设",
                        systemImage: diverged ? "exclamationmark.triangle" : "link"
                    )
                    .font(.headline)
                    .foregroundStyle(diverged ? Color.orange : .primary)
                    ForEach(Array(points.enumerated()), id: \.element.agentID) { entry in
                        let point = entry.element
                        HStack(spacing: 6) {
                            Image(
                                systemName: Fingerprint.sha256OfDirectory(point.directory) == skill.sha256
                                    ? "checkmark.circle" : "exclamationmark.triangle"
                            )
                            .foregroundStyle(
                                Fingerprint.sha256OfDirectory(point.directory) == skill.sha256
                                    ? Color.green : Color.orange
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
                        Button("以此版本更新所有落点…") {
                            confirmUpdateAll = true
                        }
                        .disabled(env.store.state.operation.inFlight != nil)
                    }
                }
            }
        }
    }

    private var motion: MotionPolicy { env.motionPolicy }

    private func previewSection(_ skill: Skill) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("SKILL.md 预览", systemImage: "doc.text")
                .font(.headline)
            if let attributed = try? AttributedString(markdown: previewMarkdown(skill)) {
                Text(attributed)
                    .font(.body)
                    .animation(motion.animation(for: .detailTransition), value: skill.id)
            }
        }
    }

    private func filesSection(_ skill: Skill) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("文件清单（\(skill.fileCount)）", systemImage: "doc.on.doc")
                .font(.headline)
            let subpaths = (try? FileManager.default.subpathsOfDirectory(atPath: skill.directory.path)) ?? []
            ForEach(Array(subpaths.prefix(40)), id: \.self) { entry in
                Text(entry)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            if subpaths.count > 40 {
                Text("…共 \(subpaths.count) 项").font(.caption).foregroundStyle(.tertiary)
            }
        }
    }

    private func historySection(_ skill: Skill) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("操作历史", systemImage: "clock.arrow.circlepath")
                .font(.headline)
            let records = env.history.recent(limit: 8).filter { $0.name == skill.name }
            if records.isEmpty {
                Text("暂无操作记录").font(.caption).foregroundStyle(.tertiary)
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
            Label("快照历史", systemImage: "camera.on.rectangle")
                .font(.headline)
            let snapshots = env.snapshots.snapshots(skillID: skill.id)
            if snapshots.isEmpty {
                Text("暂无快照（内容变化时自动记录）").font(.caption).foregroundStyle(.tertiary)
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
                    .help("恢复此版本（恢复前会先快照当前内容）")
                }
            }
        }
    }

    // MARK: 辅助

    private func previewMarkdown(_ skill: Skill) -> String {
        let url = skill.directory.appendingPathComponent("SKILL.md")
        if let content = try? String(contentsOf: url, encoding: .utf8) {
            return content
        }
        return "（SKILL.md 不存在）"
    }

    private func scopeText(_ skill: Skill) -> String {
        switch skill.scope {
        case let .global(owners): "全局（\(owners.joined(separator: "、"))）"
        case let .agentOnly(agentID): "Agent 专属（\(agentID)）"
        case let .project(agentID, root): "项目（\(agentID) · \(root.tagName)）"
        case let .multiAgent(ids): "同铺设（\(ids.joined(separator: "、"))）"
        }
    }

    private func directionText(_ direction: OperationDirection) -> String {
        switch direction {
        case .disable: "禁用"
        case .enable: "恢复启用"
        case .snapshotRestore: "快照恢复"
        case .delete: "删除"
        case .distribute: "分发安装"
        case .updateLandingPoints: "更新铺设落点"
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
                    .help("移除标签")
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
        VStack(alignment: .leading, spacing: 16) {
            Label("安装「\(skill.name)」到其他 agent", systemImage: "arrow.up.circle")
                .font(.headline)
            Text("复制语义：来源不动；同名冲突不覆盖（一致则提示已铺设）。")
                .font(.caption)
                .foregroundStyle(.secondary)

            let targets = availableTargets
            if targets.isEmpty {
                ContentUnavailableView(
                    "没有可用目标",
                    systemImage: "tray",
                    description: Text("先扫描出已安装的 agent 才能安装")
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
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("安装") {
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
        VStack(alignment: .leading, spacing: 16) {
            Label("从 git 安装 skill", systemImage: "arrow.down.circle")
                .font(.headline)
            HStack {
                TextField("https://…/repo.git 或 ~/本地仓库路径", text: $urlText)
                    .textFieldStyle(.roundedBorder)
                Button("查找候选") {
                    Task { await propose() }
                }
                .disabled(urlText.trimmingCharacters(in: .whitespaces).isEmpty || proposing)
            }

            if proposing {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("正在 clone / 校验…").foregroundStyle(.secondary)
                }
            }

            if proposalStage {
                if candidates.isEmpty {
                    Text("未发现合法 skill（检查 URL 或换本地路径形式）")
                        .foregroundStyle(.secondary)
                } else {
                    Text("勾选要安装的 skill：").font(.callout)
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

                    Picker("安装到", selection: $targetRoot) {
                        ForEach(targetChoices, id: \.self) { root in
                            Text(root.path).tag(root as URL?)
                        }
                    }
                    .frame(maxWidth: 360)
                }
            }

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("安装") {
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
