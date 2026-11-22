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

    /// 挂载托盘图标；成功返回 true，失败（桌面环境无托盘支持等）返回 false 由界面内提示降级。
    /// descriptor 携带菜单文案（摘要行 + 各菜单项标签，随界面语言）；
    /// actions 为菜单动作（平台栈自行把回调桥接回主线程）。
    /// v1 默认返回 false：macOS 走 MenuBarExtra，不经过本协议。
    @discardableResult func mountTray(_ descriptor: TrayDescriptor, actions: TrayActions) -> Bool

    /// 卸载托盘图标（v1 默认空实现，同上）。
    func unmountTray()
}

/// 托盘菜单文案（挂载时由调用方按当前界面语言组装）。
public struct TrayDescriptor: Sendable {
    /// 摘要行（不可点，如 "2 agents · 12 skills"）。
    public let summary: String
    /// 「打开主窗口」。
    public let openMainWindowTitle: String
    /// 「立即扫描」。
    public let scanNowTitle: String
    /// 「退出」。
    public let quitTitle: String
    /// agent 状态行（对齐 macOS 菜单面板 MenuSummarySection：每 agent 一行，点击筛选）。
    public let agentRows: [TrayAgentRow]

    public init(
        summary: String,
        openMainWindowTitle: String,
        scanNowTitle: String,
        quitTitle: String,
        agentRows: [TrayAgentRow] = []
    ) {
        self.summary = summary
        self.openMainWindowTitle = openMainWindowTitle
        self.scanNowTitle = scanNowTitle
        self.quitTitle = quitTitle
        self.agentRows = agentRows
    }
}

/// 托盘菜单的 agent 行（名称 + skill 计数；id 供「点击筛选该 agent」回传）。
public struct TrayAgentRow: Sendable {
    public let id: String
    /// 展示名（如 "Claude Code"）。
    public let name: String
    public let skillCount: Int

    public init(id: String, name: String, skillCount: Int) {
        self.id = id
        self.name = name
        self.skillCount = skillCount
    }
}

/// 托盘菜单动作集（mountTray 注入；实现方保证从平台事件循环桥接回主线程执行）。
public struct TrayActions: Sendable {
    /// 「打开主窗口」。
    public let openMainWindow: @MainActor @Sendable () -> Void
    /// 「立即扫描」。
    public let scanNow: @MainActor @Sendable () -> Void
    /// agent 行点击：打开主窗口并筛选该 agent（对齐 macOS 菜单面板左键语义）。
    public let openAgent: @MainActor @Sendable (String) -> Void

    public init(
        openMainWindow: @escaping @MainActor @Sendable () -> Void,
        scanNow: @escaping @MainActor @Sendable () -> Void,
        openAgent: @escaping @MainActor @Sendable (String) -> Void = { _ in }
    ) {
        self.openMainWindow = openMainWindow
        self.scanNow = scanNow
        self.openAgent = openAgent
    }
}

extension PlatformAdapter {
    public func mountTray(_ descriptor: TrayDescriptor, actions: TrayActions) -> Bool { false }
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
