// Linux GUI 入口（SCUI App 装配；macOS 入口见 AgentKeeperApp.swift）。
// os 条件编译纪律允许：本文件为可执行入口。
#if os(Linux)
import SwiftCrossUI
import Gtk3Backend
import AgentKeeperShared
import AgentKeeperUILinux
import AppCore
import DomainKit

/// Linux 主装配：主窗口（三面板）+ 设置窗口（独立 Window，工具行「设置」按钮经
/// openWindow(id:) 打开）。环境组装根 AppEnvironment 注入 LinuxPlatformAdapter
/// （xdg-open/zenity/gsettings/AppIndicator-dlopen）。
@main
struct AgentKeeperLinuxApp: App {
    typealias Backend = Gtk3Backend

    var backend = Gtk3Backend()

    // 组装根：@State 持有外部 @Observable 类（PoC 结论：SCUI 状态体系直通接入）
    @State private var env = AppEnvironment(adapter: LinuxPlatformAdapter())

    var body: some Scene {
        // 主窗口：引导与主题均由 env（@Observable）驱动——设置窗口改配置即时生效
        WindowGroup("AgentKeeper", id: "main") {
            LinuxRootView(env: env)
                .preferredColorScheme(linuxColorScheme(for: env.settings.appearance))
                .frame(minWidth: 1100, minHeight: 680)
        }

        // 设置窗口（独立 Window：默认不随启动打开，openWindow(id: "settings") 唤起）
        Window(env.l10n.settingsWindow, id: "settings") {
            LinuxSettingsView(env: env)
                .preferredColorScheme(linuxColorScheme(for: env.settings.appearance))
                .frame(minWidth: 460, minHeight: 520)
        }
    }
}
#endif
