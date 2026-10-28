import SwiftUI
import AgentKeeperUI
import AppCore
import DomainKit

@main
struct AgentKeeperApp: App {
    @State private var env = AppEnvironment()
    @State private var showOnboarding = true

    var body: some Scene {
        // 单例窗口：MenuBarExtra「打开主窗口」复用已有窗口，而不是新建多个。
        Window("AgentKeeper", id: "main") {
            Group {
                if showOnboarding {
                    OnboardingView(hasCompleted: onboardingBinding)
                } else {
                    RootView()
                }
            }
            .environment(env)
            .frame(minWidth: 1000, minHeight: 640)
            .task {
                await env.bootstrap()
            }
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("立即扫描") {
                    Task { await env.scanNow() }
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(env.store.state.scan.phase == .running)
            }
        }

        MenuBarExtra("AgentKeeper", systemImage: "sparkle.magnifyingglass") {
            MenuSummarySection(env: env)
        }
    }

    private var onboardingBinding: Binding<Bool> {
        Binding(
            get: { showOnboarding },
            set: { newValue in
                showOnboarding = newValue
            }
        )
    }
}
