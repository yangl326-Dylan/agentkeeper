import SwiftUI
import AppCore

/// 首启引导页（6.6）：说明扫描机制、目录授权与 ~/.agentkeeper 数据目录契约。
public struct OnboardingView: View {
    @Environment(AppEnvironment.self) private var env
    @Binding var hasCompleted: Bool

    public init(hasCompleted: Binding<Bool>) {
        self._hasCompleted = hasCompleted
    }

    public var body: some View {
        VStack(spacing: 28) {
            VStack(spacing: 10) {
                Image(systemName: "shippingbox.and.arrow.backward.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.tint)
                Text("欢迎使用 AgentKeeper").font(.title).bold()
                Text("扫描本机 AI agent 的 skills，标记作用域，安全禁用与快照。")
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 32)

            VStack(alignment: .leading, spacing: 14) {
                explainRow(
                    icon: "dot.radiowaves.left.and.right",
                    title: "一次全量扫描",
                    detail: "只读扫描各 agent 的标准 skill 目录；外部改动由系统级文件事件自动增量跟随。"
                )
                explainRow(
                    icon: "lock.shield",
                    title: "目录授权",
                    detail: "扫描仅限用户级与已知项目根，永不递归整个家目录。受限目录会以诊断形式提示你手动授权。"
                )
                explainRow(
                    icon: "tray.full",
                    title: "~/.agentkeeper 数据目录",
                    detail: "禁用区、快照、历史与缓存都会存放在这里；文件系统是唯一真相，任何时刻都可以从磁盘重建。"
                )
                explainRow(
                    icon: "hand.raised",
                    title: "不覆盖不打扰",
                    detail: "冲突一律中止并展示明细；禁用/恢复使用原子搬移 + 失败回滚。"
                )
            }
            .padding(24)
            .background(ClaudePalette.card, in: RoundedRectangle(cornerRadius: 14))

            Button {
                hasCompleted = true // @Binding 直写
                Task { await env.scanNow() }
            } label: {
                Text("开始扫描本机").controlSize(.large)
            }
            .keyboardShortcut(.defaultAction)
            .padding(.bottom, 32)
        }
        .frame(maxWidth: 520, maxHeight: 640)
        .padding(40)
    }

    private func explainRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.tint)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
