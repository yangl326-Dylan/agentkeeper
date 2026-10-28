import Foundation
import Testing
import AppKit
@testable import AgentKeeperUI

/// 启动形态保障：AgentKeeper 必须以常规前台应用运行（Dock 图标 + 应用菜单栏）。
/// 裸 SwiftPM 可执行（无 bundle）会被 LaunchServices 登记为 BackgroundOnly——
/// 无 Dock、无菜单栏归属（⌘R 等命令不可达）。见 AppStartup.ensureRegularApp。
@MainActor
@Suite struct AppStartupTests {
    @Test func ensureRegularAppForcesRegularPolicy() {
        let app = NSApplication.shared
        let previous = app.activationPolicy()
        defer { app.setActivationPolicy(previous) }

        // 模拟被登记成后台形态（prohibited = 无 UI 形态）
        app.setActivationPolicy(.prohibited)
        #expect(app.activationPolicy() == .prohibited)

        AppStartup.ensureRegularApp()
        #expect(app.activationPolicy() == .regular)
    }

    @Test func ensureRegularAppIsIdempotent() {
        let app = NSApplication.shared
        let previous = app.activationPolicy()
        defer { app.setActivationPolicy(previous) }

        app.setActivationPolicy(.regular)
        AppStartup.ensureRegularApp()
        AppStartup.ensureRegularApp()
        #expect(app.activationPolicy() == .regular)
    }
}
