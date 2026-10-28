import SwiftUI
import AppCore
import DomainKit
import InfraKit

/// 三面板主壳：侧栏（导航树）→ 列表（筛选/搜索）→ 详情。
struct RootView: View {
    var body: some View {
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

    var body: some View {
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
            }
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
        }
    }
}

// MARK: - 状态条（非阻断）

struct ScanStatusStrip: View {
    let scan: ScanPhaseState

    var body: some View {
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

// MARK: - 列表（筛选/搜索）

struct SkillListView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var searchText = ""
    @State private var scopeFilter: Set<ScopeKind> = []

    var body: some View {
        let query = filtered()
        List(selection: selectedSkillBinding) {
            ForEach(query) { skill in
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
        .searchable(text: $searchText, placement: .automatic, prompt: "搜索名称 / 描述 / 项目")
        .navigationTitle("Skills")
        .toolbar { toolbarContent }
        .animation(motion.animation(for: .listTransition), value: query.map({ $0.id }))
    }

    // MARK: 选择

    private var selectedSkillBinding: Binding<String?> {
        Binding(
            get: { env.selectedSkillID },
            set: { env.selectedSkillID = $0 }
        )
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
            } label: {
                Label("筛选", systemImage: "line.3.horizontal.decrease.circle")
            }
            Button {
                Task { await env.scanNow() }
            } label: {
                Label("立即扫描", systemImage: "arrow.clockwise")
            }
            .disabled(env.store.state.scan.phase == .running)
        }
    }

    private func scopeToggle(_ kind: ScopeKind) -> Binding<Bool> {
        Binding(
            get: { scopeFilter.contains(kind) },
            set: { on in
                if on { scopeFilter.insert(kind) } else { scopeFilter.remove(kind) }
            }
        )
    }

    private var motion: MotionPolicy { env.motionPolicy }

    // MARK: 数据

    private func filtered() -> [Skill] {
        var query = CatalogQuery.initial
        query.scopeKinds = scopeFilter
        query.searchText = searchText
        return query.apply(catalog: env.catalogStore.current)
    }

    private func token(of skill: Skill) -> StatusToken {
        if skill.status == .disabled { return .disabled }
        return .enabled
    }

    private func subtitle(_ skill: Skill) -> String {
        var parts: [String] = []
        if let agent = skill.owners.first { parts.append(agent) }
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

// MARK: - 详情面板

struct SkillDetailView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var pendingError: String?

    var body: some View {
        if let skill = selectedSkill {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header(skill)
                    scopeBadge(skill)
                    Divider()
                    previewSection(skill)
                    Divider()
                    filesSection(skill)
                    Divider()
                    historySection(skill)
                    snapshotsSection(skill)
                }
                .padding(24)
            }
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .transition(.opacity)
        } else {
            ContentUnavailableView("选择一个 Skill", systemImage: "square.on.rounded.square")
        }
    }

    private var selectedSkill: Skill? {
        guard let id = env.selectedSkillID else { return nil }
        return env.catalogStore.current.first { $0.id == id }
    }

    private var motion: MotionPolicy { env.motionPolicy }

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
    }

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
