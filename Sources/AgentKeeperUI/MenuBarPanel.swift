import SwiftUI
import AppKit
import DomainKit
import AppCore

// MARK: - 头部摘要行

/// 头部：面板锚点 + 摘要（tabular 数字，右对齐灰阶层级）。
struct MenuBarHeaderRow: View {
    let agentCount: Int
    let totalSkills: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "shippingbox.and.arrow.backward.fill")
                .font(.system(size: 12))
                .foregroundStyle(ClaudePalette.accent)
            Text("AgentKeeper")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Text("\(agentCount) agents · \(totalSkills) skills")
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }
}

// MARK: - agent 状态行

/// agent 行：语义图标 + 名称 + tabular skill 数；hover 高亮；点击在 Finder 打开其 skill 根目录。
struct MenuBarAgentRow: View {
    let name: String
    let icon: String
    let skillCount: Int
    let targetDirectory: URL?

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(name)
                .font(.system(size: 12))
                .lineLimit(1)
            Spacer()
            Text("\(skillCount)")
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(hovering ? Color(nsColor: .secondarySystemFill) : .clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            guard let targetDirectory else { return }
            NSWorkspace.shared.activateFileViewerSelecting([targetDirectory])
        }
        .help("在 Finder 中打开该 agent 的 skills 目录")
    }
}

// MARK: - 操作区

/// 操作区：全宽主按钮（accent）+ 扫描行 + 底部退出小字。
struct MenuPanelActions: View {
    let isScanning: Bool
    let onOpenMain: () -> Void
    let onScan: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Button(action: onOpenMain) {
                Text("打开主窗口")
                    .font(.system(size: 12, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
            }
            .buttonStyle(.borderedProminent)
            .tint(ClaudePalette.accent)

            Button(action: onScan) {
                HStack {
                    Text(isScanning ? "正在扫描…" : "立即扫描")
                        .font(.system(size: 12))
                    Spacer()
                    if isScanning {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Color(nsColor: .secondarySystemFill), in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isScanning)

            Button(action: onQuit) {
                HStack {
                    Text("退出 AgentKeeper")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("⌘Q")
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12)
                .padding(.top, 4)
            }
            .buttonStyle(.plain)
        }
    }
}
