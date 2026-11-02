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
            // 引导与主题均由 env（@Observable）驱动——Settings 场景改配置即时生效
            AppRootView(initialHasCompleted: env.firstRun.hasCompletedOnboarding)
                .environment(env)
                .tint(ClaudePalette.accent)
                .background(ClaudePalette.background)
                .preferredColorScheme(env.settings.effectiveColorScheme)
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

        // 官方设置窗口（⌘, 自动接入 app 菜单）
        Settings {
            AppSettingsView()
                .environment(env)
                .tint(ClaudePalette.accent)
                .preferredColorScheme(env.settings.effectiveColorScheme)
        }

        // 菜单栏：自定义「收藏匣」template 字形（MenuBarIconTests 覆盖）——
        // SF 同款箱子仅是符号近似；闭包 label 携带 NSImage(template) 系统明暗自适应
        MenuBarExtra {
            MenuSummarySection(env: env)
        } label: {
            Image(nsImage: MenuBarIcon.templateImage())
                .accessibilityLabel("AgentKeeper")
        }
    }
}
