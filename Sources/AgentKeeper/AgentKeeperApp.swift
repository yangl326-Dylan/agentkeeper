import SwiftUI
import AgentKeeperUI
import AppCore
import DomainKit

@main
struct AgentKeeperApp: App {
    @State private var env = AppEnvironment()

    init() {
        // 裸可执行形态兜底：强制常规前台应用（Dock 图标 + 应用菜单栏归属）
        AppStartup.ensureRegularApp()
    }

    var body: some Scene {
        // 单例窗口：MenuBarExtra「打开主窗口」复用已有窗口，而不是新建多个。
        Window("AgentKeeper", id: "main") {
            // 引导切换状态在 AppRootView（View 级 @State）——App 级 @State 从
            // Window 内容写入不会触发场景重评估，曾致引导页卡死。
            AppRootView(initialHasCompleted: env.firstRun.hasCompletedOnboarding)
                .environment(env)
                .tint(ClaudePalette.accent)
                .background(ClaudePalette.background)
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
}
