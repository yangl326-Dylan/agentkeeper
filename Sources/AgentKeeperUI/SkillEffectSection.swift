import SwiftUI
import AppCore
import DomainKit

/// 详情面板生效关系区块：同名遮蔽判定 + 串扰说明；无关系信息时不渲染（零噪音）。
/// 判定来自扫描期（官方优先级硬编码），区块只做展示。
struct SkillEffectSection: View {
    let skill: Skill
    var l10n: L10n = L10n(lang: .zhHans)

    var body: some View {
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(l10n.effectSectionTitle)
                    .font(.headline)
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: line.isBlurred ? "eye.slash" : "eye")
                            .foregroundStyle(line.isBlurred ? .yellow : .secondary)
                            .font(.caption)
                        Text(line.text)
                            .font(.callout)
                    }
                }
                if case .agentOnly = skill.scope {
                    Text(l10n.effectCrossNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private struct Line {
        let text: String
        /// true = 被遮蔽（eye.slash 黄）
        let isBlurred: Bool
    }

    private var lines: [Line] {
        var result: [Line] = []
        if skill.shadowedBy != nil {
            result.append(Line(text: l10n.effectShadowedNotice, isBlurred: true))
        }
        if skill.shadowedCount > 0 {
            result.append(Line(text: l10n.effectShadowsCount(skill.shadowedCount), isBlurred: false))
        }
        if case let .multiAgent(ids) = skill.scope {
            result.append(Line(text: l10n.effectMultiAgent(ids.joined(separator: l10n.listSeparator)), isBlurred: false))
        }
        return result
    }
}
