#if os(Linux)
import Foundation
import SwiftCrossUI
import AgentKeeperShared
import AppCore
import DomainKit

/// 总览仪表盘（未选中 skill 时的主界面）：总量/agent 分布/作用域分布/最近扫描。
/// 成对文件：Sources/AgentKeeperUI/OverviewDashboard.swift（数据同源 overviewModel()，
/// 渲染为 Linux 简版卡片流——v1 范围内不追求 macOS 仪表盘全量视觉）。
struct LinuxOverviewDashboard: View {
    let env: AppEnvironment

    /// 内容直接内嵌父级详情 ScrollView（勿再包一层滚动容器——嵌套 ScrolledWindow
    /// 会让滚动语义含糊，且外层已提供背景与内边距）。
    var body: some View {
        let l = env.l10n
        let model = env.overviewModel()
        VStack(alignment: .leading, spacing: 16) {
                Text(l.overviewTitle)
                    .font(.title)
                    .emphasized()
                    .foregroundColor(LinuxPalette.textPrimary)
                if model.totalSkills == 0 {
                    Text(l.overviewNotScanned)
                        .font(.body)
                        .foregroundColor(LinuxPalette.textSecondary)
                        // SCUI 的 Text 在非理想高度上下文里会截断（文档 §Text）；
                        // 显式允许纵向伸展以换行显示整句提示。
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    HStack(spacing: 12) {
                        LinuxOverviewCard(title: l.overviewTitle, value: "\(model.totalSkills)")
                        LinuxOverviewCard(title: l.sectionAgents, value: "\(model.installedAgents)")
                        LinuxOverviewCard(title: l.overviewTags, value: "\(model.tagCount)")
                    }
                    LinuxOverviewCard(
                        title: l.overviewScopeDistribution,
                        value: scopeDistributionText(model),
                        wide: true
                    )
                    if let lastScan = model.lastScanAt {
                        Text(l.overviewLastScan(Self.timeText(lastScan)))
                            .font(.caption)
                            .foregroundColor(LinuxPalette.textSecondary)
                    }
                    // agent 分布行
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(model.agentEntries) { entry in
                            HStack(spacing: 8) {
                                Text("▢")
                                    .font(.system(size: 11))
                                    .foregroundColor(LinuxPalette.textSecondary)
                                Text(entry.id)
                                    .font(.body)
                                    .foregroundColor(LinuxPalette.textPrimary)
                                Spacer(minLength: 0)
                                Text("\(entry.skillCount)")
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(LinuxPalette.textSecondary)
                            }
                            .padding(6)
                            .background(LinuxPalette.card)
                        }
                    }
                }
            }
    }

    private func scopeDistributionText(_ model: OverviewModel) -> String {
        let l = env.l10n
        let entries: [String] = [
            model.scopeCounts[.global].map { "\(l.scopeGlobal) \($0)" },
            model.scopeCounts[.agentOnly].map { "\(l.scopeAgentOnly) \($0)" },
            model.scopeCounts[.project].map { "\(l.scopeProject) \($0)" },
            model.scopeCounts[.multiAgent].map { "\(l.scopeMultiAgent) \($0)" },
        ].compactMap { $0 }
        return entries.joined(separator: " · ")
    }

    private static func timeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}

/// 总览统计卡（数值 + 标题）。
struct LinuxOverviewCard: View {
    let title: String
    let value: String
    var wide = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.title2)
                .emphasized()
                .foregroundColor(LinuxPalette.textPrimary)
            Text(title)
                .font(.caption)
                .foregroundColor(LinuxPalette.textSecondary)
                .lineLimit(1)
        }
        .padding(12)
        .frame(minWidth: 100, maxWidth: wide ? .infinity : 140, alignment: .leading)
        .background(LinuxPalette.card)
    }
}
#endif
