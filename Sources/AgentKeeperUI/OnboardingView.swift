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
        let l = env.l10n
        VStack(spacing: 28) {
            VStack(spacing: 10) {
                Image(systemName: "shippingbox.and.arrow.backward.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.tint)
                Text(l.onboardingWelcome).font(.title).bold()
                Text(l.onboardingSubtitle)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 32)

            VStack(alignment: .leading, spacing: 14) {
                explainRow(
                    icon: "dot.radiowaves.left.and.right",
                    title: l.onboardingScanTitle,
                    detail: l.onboardingScanDetail
                )
                explainRow(
                    icon: "lock.shield",
                    title: l.onboardingAuthTitle,
                    detail: l.onboardingAuthDetail
                )
                explainRow(
                    icon: "tray.full",
                    title: l.onboardingDataDirTitle,
                    detail: l.onboardingDataDirDetail
                )
                explainRow(
                    icon: "hand.raised",
                    title: l.onboardingNoOverrideTitle,
                    detail: l.onboardingNoOverrideDetail
                )
            }
            .padding(24)
            .background(ClaudePalette.card, in: RoundedRectangle(cornerRadius: 14))

            Button {
                hasCompleted = true // @Binding 直写
                Task { await env.scanNow() }
            } label: {
                Text(l.onboardingStartScan).controlSize(.large)
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
