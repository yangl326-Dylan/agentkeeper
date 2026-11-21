// macOS 平台适配器：AppKit/NSWorkspace 实现（本文件属 macOS UI 栈，Linux 上编为空模块）。
#if os(macOS)
import AppKit
import AgentKeeperShared
import Foundation

/// `PlatformAdapter` 的 macOS 实现：收敛 AppKit 触点，共享层只见协议。
/// 行为与原散落在 UI 各处的 NSWorkspace/NSApplication 调用一一对应（零行为变化）。
public struct MacPlatformAdapter: PlatformAdapter {
    public init() {}

    public var isReduceMotionEnabled: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// 在 Finder 中显示并选中目标（同原 FilesList 的 activateFileViewerSelecting）。
    public func revealInFileManager(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// 系统默认方式打开（同原 NSWorkspace.open）。
    public func openURL(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    /// 目录选择面板（异步 begin，不阻塞 MainActor）。
    public func openDirectoryPicker() async -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        return await withCheckedContinuation { continuation in
            panel.begin { response in
                continuation.resume(returning: response == .OK ? panel.url : nil)
            }
        }
    }

    /// 前台激活（同原 NSApplication.activate(ignoringOtherApps: true)）。
    public func activateApp() {
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    /// 退出应用（原 UpdateModel.terminate 的 NSApplication.terminate 路径）。
    public func terminateApp() {
        NSApplication.shared.terminate(nil)
    }

    // mountTray/unmountTray：macOS 托盘走 MenuBarExtra（协议扩展默认空实现即可）。
}
#endif
