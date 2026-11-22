#if os(Linux)
import Foundation
import AgentKeeperShared

/// `PlatformAdapter` 的 Linux 实现（add-linux-app 任务 3.6/3.7）：
/// - 打开文件/目录/URL → xdg-open
/// - 目录选择器 → zenity --file-selection --directory（zenity 缺失/取消 → nil）
/// - 减少动效探测 → gsettings org.gnome.desktop.interface enable-animations
/// - 托盘 → AppIndicator（dlopen libayatana-appindicator3；任一步失败返回 false 降级）
/// - terminateApp → exit(0)；activateApp → no-op（单窗口 GTK 应用无需激活协议）
/// （成对文件：Sources/AgentKeeperUI/MacPlatformAdapter.swift。）
public struct LinuxPlatformAdapter: PlatformAdapter, Sendable {
    /// 托盘状态（class 引用持有——struct 适配器共享同一托盘实例）。
    private let tray = AppIndicatorTray()
    /// dlopen 注入层（测试经 init 注入 mock）。
    private let loader: any DynamicLibraryLoader

    public init(loader: any DynamicLibraryLoader = DlDynamicLibraryLoader()) {
        self.loader = loader
    }

    // MARK: PlatformAdapter

    /// GNOME「动画」关闭即视为减少动效开启；gsettings 不可用/失败 → false（保守：不减弱）。
    public var isReduceMotionEnabled: Bool {
        // 任何 env/前缀形式的进程生成会被环境拦截——直接 Process 裸调
        guard let output = LinuxProcessRunner.output(
            executable: LinuxProcessCommands.gsettingsExecutable,
            arguments: LinuxProcessCommands.gsettingsReadArguments()
        ) else { return false }
        return !LinuxProcessCommands.parseEnableAnimations(output: output)
    }

    /// 在文件管理器中定位：打开所在目录（目标本身为目录则直接打开）。
    public func revealInFileManager(_ url: URL) {
        LinuxProcessRunner.launch(
            executable: LinuxProcessCommands.xdgOpenExecutable,
            arguments: LinuxProcessCommands.revealArguments(url)
        )
    }

    /// 系统默认方式打开（文件/目录/下载页 URL）。
    public func openURL(_ url: URL) {
        LinuxProcessRunner.launch(
            executable: LinuxProcessCommands.xdgOpenExecutable,
            arguments: LinuxProcessCommands.xdgOpenArguments(url)
        )
    }

    /// zenity 目录选择（阻塞型对话框：后台线程等待，协议本身 async 不占主线程）。
    public func openDirectoryPicker() async -> URL? {
        let executable = LinuxProcessCommands.zenityExecutable
        let arguments = LinuxProcessCommands.zenityDirectoryArguments()
        let output = await Task.detached(priority: .userInitiated) {
            LinuxProcessRunner.output(executable: executable, arguments: arguments)
        }.value
        guard let path = output.flatMap({ LinuxProcessCommands.parseZenityPath(output: $0) }) else {
            return nil
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    /// 前台激活：Linux 单实例 GTK 应用由窗口管理器管理焦点，no-op。
    public func activateApp() {}

    /// 退出应用（托盘退出菜单 / 更新流程）。
    public func terminateApp() {
        exit(0)
    }

    /// AppIndicator 托盘；退出菜单由适配器自行合成（terminateApp）。
    @discardableResult
    public func mountTray(_ descriptor: TrayDescriptor, actions: TrayActions) -> Bool {
        tray.mount(
            descriptor: descriptor,
            iconName: "agentkeeper", // hicolor 真图标（与 macOS AppIcon 同源；.deb 安装后经主题解析）
            actions: actions,
            quit: { [adapter = self] in adapter.terminateApp() },
            loader: loader
        )
    }

    public func unmountTray() {
        tray.unmount()
    }
}
#endif
