import Foundation

/// 平台行为适配点（add-linux-app 决策 2）：共享展示层只见本协议，
/// 每个栈各自提供实现（macOS=AppKit/NSWorkspace；Linux=xdg-open/AppIndicator）。
/// AppEnvironment 经 init 注入；缺省 `NullPlatformAdapter`（测试与无桌面环境兜底）。
/// @MainActor：实现全部触碰平台 UI API（AppKit/GTK），调用方（AppEnvironment）均为 MainActor。
@MainActor
public protocol PlatformAdapter {
    /// 系统辅助功能「减少动态效果」当前是否开启（reduceMotion 跟随探测）。
    var isReduceMotionEnabled: Bool { get }

    /// 在系统文件管理器中显示定位该 URL（macOS=Finder；Linux=xdg-open 所在目录）。
    func revealInFileManager(_ url: URL)

    /// 用系统默认方式打开 URL（文件/目录/下载页等）。
    func openURL(_ url: URL)

    /// 目录选择器（导入/分发落点）；用户取消返回 nil。
    func openDirectoryPicker() async -> URL?

    /// 把应用带到前台（托盘/菜单栏入口点击后唤起主窗口时用）。
    func activateApp()

    /// 退出应用（更新安装后重启流程、托盘退出菜单）。
    func terminateApp()

    /// 挂载托盘图标（v1 默认空实现：macOS 走 MenuBarExtra，不经过本协议）。
    func mountTray()

    /// 卸载托盘图标（v1 默认空实现，同上）。
    func unmountTray()
}

extension PlatformAdapter {
    public func mountTray() {}
    public func unmountTray() {}
}

/// 空实现：全部行为为无操作。默认注入用（单测、CLI 侧组装、无桌面会话）——
/// 共享层任何平台触点都不得直接依赖具体平台 API，一律经本协议。
@MainActor
public struct NullPlatformAdapter: PlatformAdapter {
    public init() {}

    public var isReduceMotionEnabled: Bool { false }

    public func revealInFileManager(_ url: URL) {}
    public func openURL(_ url: URL) {}
    public func openDirectoryPicker() async -> URL? { nil }
    public func activateApp() {}
    public func terminateApp() {}
}
