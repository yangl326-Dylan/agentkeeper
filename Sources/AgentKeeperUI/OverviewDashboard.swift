#if os(macOS)
import Foundation
import SwiftUI
import AgentKeeperShared
import AppCore
import DomainKit

// OverviewModel（纯聚合模型）已移入 AgentKeeperShared（双栈共用同一数据底座）；
// 本文件只保留 macOS SwiftUI 仪表盘视图。

/// 总览仪表盘（MangoDisk 式扫描产出全貌：统计卡 + 作用域分布 + agent 卡片）。
@MainActor
public struct OverviewDashboard: View {
    @Environment(AppEnvironment.self) private var env

    public init() {}

    public var body: some View {
        ScrollView {
            OverviewContent()
        }
    }
}

/// 仪表盘正文（独立 View 节点：@Environment 在渲染期解析；
/// ScrollView 离屏渲染空白，快照直接引用本节点）。
@MainActor
struct OverviewContent: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        // 模型由 env memoize（catalog version + agent 数 + tag revision + 最近扫描 键控）——
        // body 不再逐帧做 skills×agents 全量统计
        let env = self.env
        let model = env.overviewModel()
        return VStack(alignment: .leading, spacing: 20) {
            header(model)
            statCards(model)
            scopeSection(model)
            agentsSection(model)
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func header(_ model: OverviewModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(env.l10n.overviewTitle, systemImage: "shippingbox.and.arrow.backward.fill")
                .font(.title2.bold())
            if let at = model.lastScanAt {
                Text(env.l10n.overviewLastScan(OverviewDashboard.clockText(at)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(env.l10n.overviewNotScanned)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func statCards(_ model: OverviewModel) -> some View {
        HStack(spacing: 14) {
            statCard(value: model.totalSkills, label: "Skills", icon: "square.stack.3d.up")
            statCard(value: model.installedAgents, label: "Agents", icon: "externaldrive.badge.checkmark")
            statCard(value: model.tagCount, label: env.l10n.overviewTags, icon: "tag")
        }
    }

    private func statCard(value: Int, label: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(label, systemImage: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(ClaudePalette.card, in: RoundedRectangle(cornerRadius: 12))
    }

    private func scopeSection(_ model: OverviewModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(env.l10n.overviewScopeDistribution, systemImage: "scope")
                .font(.headline)
            let total = max(model.totalSkills, 1)
            ForEach([ScopeKind.global, .agentOnly, .project, .multiAgent], id: \.self) { kind in
                let count = model.scopeCounts[kind] ?? 0
                HStack(spacing: 10) {
                    Text(kind.label(env.l10n))
                        .font(.callout)
                        .frame(width: 92, alignment: .leading)
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.quaternary.opacity(0.4))
                            Capsule()
                                .fill(ClaudePalette.accent)
                                .frame(width: proxy.size.width * CGFloat(count) / CGFloat(total))
                        }
                    }
                    .frame(height: 8)
                    Text("\(count)")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 34, alignment: .trailing)
                }
            }
        }
    }

    private func agentsSection(_ model: OverviewModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Agents", systemImage: "person.crop.square")
                .font(.headline)
            if model.agentEntries.isEmpty {
                Text(env.l10n.sidebarNoAgents)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.agentEntries) { entry in
                    HStack {
                        Image(systemName: "externaldrive.badge.checkmark")
                            .foregroundStyle(ClaudePalette.accent)
                        Text(entry.id)
                        Spacer()
                        Text("\(entry.skillCount) skills")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
}

extension OverviewDashboard {
    private static let clockFormatter = DateFormatter()

    static func clockText(_ date: Date) -> String {
        clockFormatter.dateFormat = "HH:mm:ss"
        return clockFormatter.string(from: date)
    }
}

extension ScopeKind {
    func label(_ l10n: L10n) -> String {
        switch self {
        case .global: l10n.scopeGlobal
        case .agentOnly: l10n.scopeAgentOnly
        case .project: l10n.scopeProject
        case .multiAgent: l10n.scopeMultiAgent
        }
    }
}

#endif
