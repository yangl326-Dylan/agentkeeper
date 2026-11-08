import SwiftUI
import AppCore
import DomainKit

/// 详情面板健康区块：客观问题逐条列出 + 体积事实；无问题时只显示事实行（零噪音）。
/// 同类 kind 不重复（parseDirectory 保证每类最多一条），ForEach 以 kind 为 id。
struct SkillHealthSection: View {
    let skill: Skill
    var l10n: L10n = L10n(lang: .zhHans)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(l10n.healthSectionTitle)
                .font(.headline)
            ForEach(skill.issues, id: \.kind) { issue in
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                        .font(.caption)
                    Text(l10n.healthIssueText(issue.kind))
                        .font(.callout)
                }
            }
            Text(factLine)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var factLine: String {
        let total = ByteCountFormatter.string(fromByteCount: Int64(skill.totalBytes), countStyle: .file)
        let md = ByteCountFormatter.string(fromByteCount: Int64(skill.skillMdBytes), countStyle: .file)
        return "\(total) · \(l10n.healthFilesCount(skill.fileCount)) · SKILL.md \(md)"
    }
}
