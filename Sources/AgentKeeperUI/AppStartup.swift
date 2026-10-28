import Foundation
import AppKit

/// 启动形态保障（可执行层 @main 与测试共用）。
/// 裸 SwiftPM 可执行（无 .app bundle/Info.plist）会被 LaunchServices 登记为
/// BackgroundOnly：无 Dock 图标、无应用菜单栏（⌘R 等命令不可达）。
/// 启动时显式提升为 regular；幂等，可安全重复调用。
@MainActor
public enum AppStartup {
    public static func ensureRegularApp() {
        let app = NSApplication.shared
        guard app.activationPolicy() != .regular else { return }
        app.setActivationPolicy(.regular)
    }
}
