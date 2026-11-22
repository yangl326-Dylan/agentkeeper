#if os(Linux)
import Foundation
import Testing
import AgentKeeperShared
@testable import AgentKeeperUILinux

/// Linux 平台适配器可测逻辑（任务 3.6/3.7 验收）：命令参数组装、外部输出解析、
/// 托盘 dlopen 降级判定（mock DynamicLibraryLoader；真机 dlopen 路径不进单测）。
@Suite struct LinuxPlatformAdapterTests {
    // MARK: xdg-open 参数组装

    @Test func xdgOpenArgumentsPassAbsoluteURL() throws {
        let url = URL(fileURLWithPath: "/home/user/skills/demo", isDirectory: true)
        let arguments = LinuxProcessCommands.xdgOpenArguments(url)
        #expect(arguments.count == 1)
        #expect(arguments[0] == url.absoluteString)
    }

    @Test func revealOnDirectoryOpensItself() {
        let url = URL(fileURLWithPath: "/tmp/opendir-demo", isDirectory: true)
        try? FileManager.default.createDirectory(atPath: url.path, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: url) }
        let arguments = LinuxProcessCommands.revealArguments(url)
        #expect(arguments.count == 1)
        #expect(arguments[0] == url.absoluteString)
    }

    @Test func revealOnFileOpensContainingDirectory() {
        let base = NSTemporaryDirectory()
        let directory = URL(fileURLWithPath: base).appendingPathComponent("ak-reveal-\(UUID().uuidString)", isDirectory: true)
        let file = directory.appendingPathComponent("SKILL.md")
        try? FileManager.default.createDirectory(atPath: directory.path, withIntermediateDirectories: true)
        try? "x".write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: directory) }
        let arguments = LinuxProcessCommands.revealArguments(file)
        #expect(arguments.count == 1)
        #expect(arguments[0] == directory.absoluteString)
    }

    // MARK: zenity 目录选择

    @Test func zenityArgumentsAreDirectorySelection() {
        #expect(LinuxProcessCommands.zenityDirectoryArguments() == ["--file-selection", "--directory"])
    }

    @Test func zenityPathParsing() {
        #expect(LinuxProcessCommands.parseZenityPath(output: "/home/user/pick\n") == "/home/user/pick")
        #expect(LinuxProcessCommands.parseZenityPath(output: "  /abs/path  ") == "/abs/path")
        #expect(LinuxProcessCommands.parseZenityPath(output: "") == nil) // 取消/失败（空输出）
        #expect(LinuxProcessCommands.parseZenityPath(output: "relative/path") == nil) // 非绝对路径防御
    }

    // MARK: gsettings 减少动效探测

    @Test func gsettingsArgumentsReadAnimations() {
        #expect(LinuxProcessCommands.gsettingsReadArguments()
            == ["get", "org.gnome.desktop.interface", "enable-animations"])
    }

    @Test func enableAnimationsParsing() {
        #expect(LinuxProcessCommands.parseEnableAnimations(output: "true\n") == true)
        #expect(LinuxProcessCommands.parseEnableAnimations(output: "  true ") == true)
        #expect(LinuxProcessCommands.parseEnableAnimations(output: "false") == false)
        #expect(LinuxProcessCommands.parseEnableAnimations(output: "") == false)
        // 减少动效 = 动画关闭 = parse false
        #expect(!LinuxProcessCommands.parseEnableAnimations(output: "false") == true)
    }

    // MARK: 托盘降级判定（dlopen 失败 / 符号缺失 → mountTray false）

    /// 全库打不开（AppIndicator 缺失——降级主路径）。
    @Test func trayFailsWhenLibrariesMissing() {
        var loader = MockDynamicLibraryLoader()
        loader.handleByPath = [:] // 一切 open → nil
        let tray = AppIndicatorTray()
        let mounted = tray.mount(descriptor: Self.descriptor(), iconName: "package", actions: Self.actions(), quit: {}, loader: loader)
        #expect(mounted == false)
    }

    /// 库能打开但任一必需符号缺失 → false（不抛半挂载状态）。
    @Test func trayFailsWhenAnySymbolMissing() throws {
        var loader = MockDynamicLibraryLoader()
        let appIndicator = MockHandle()
        let gtk = MockHandle()
        let gobject = MockHandle()
        loader.handleByPath = [
            "libayatana-appindicator3.so.1": appIndicator,
            "libgtk-3.so.0": gtk,
            "libgobject-2.0.so.0": gobject,
        ]
        loader.symbolNamesByHandle[appIndicator.id] = [
            "app_indicator_new", "app_indicator_set_status", "app_indicator_set_icon_full",
            "app_indicator_set_title", "app_indicator_set_menu",
        ]
        loader.symbolNamesByHandle[gtk.id] = [
            "gtk_menu_new", "gtk_menu_item_new_with_label", "gtk_menu_shell_append",
            "gtk_widget_set_sensitive",
            // gtk_widget_show_all 缺失
        ]
        loader.symbolNamesByHandle[gobject.id] = ["g_signal_connect_data"]
        #expect(AppIndicatorSymbolTable.resolve(loader: loader) == nil)
        let tray = AppIndicatorTray()
        let mounted = tray.mount(descriptor: Self.descriptor(), iconName: "package", actions: Self.actions(), quit: {}, loader: loader)
        #expect(mounted == false)
    }

    /// 全符号命中 → 符号表组装成功（mock 句柄不执行真 GTK 调用——
    /// 真机正向路径由托盘冒烟验证，单测只锁降级判定与符号解析契约）。
    @Test func traySymbolTableResolvesWhenAllSymbolsPresent() {
        var loader = MockDynamicLibraryLoader()
        let appIndicator = MockHandle()
        let gtk = MockHandle()
        let gobject = MockHandle()
        loader.handleByPath = [
            "libayatana-appindicator3.so.1": appIndicator,
            "libgtk-3.so.0": gtk,
            "libgobject-2.0.so.0": gobject,
        ]
        loader.symbolNamesByHandle[appIndicator.id] = [
            "app_indicator_new", "app_indicator_set_status", "app_indicator_set_icon_full",
            "app_indicator_set_title", "app_indicator_set_menu",
        ]
        loader.symbolNamesByHandle[gtk.id] = [
            "gtk_menu_new", "gtk_menu_item_new_with_label", "gtk_separator_menu_item_new",
            "gtk_menu_shell_append", "gtk_widget_show_all", "gtk_widget_set_sensitive",
        ]
        loader.symbolNamesByHandle[gobject.id] = ["g_signal_connect_data"]
        #expect(AppIndicatorSymbolTable.resolve(loader: loader) != nil)
    }

    /// 卸载幂等（未挂载时 unmount 不炸）。
    @Test func unmountIsIdempotent() {
        AppIndicatorTray().unmount()
    }

    // MARK: 协议降级默认（NullPlatformAdapter → false；协议签名变更同步验证）

    @Test @MainActor func nullAdapterTrayDefaultsToDegraded() {
        let adapter = NullPlatformAdapter()
        let mounted = adapter.mountTray(Self.descriptor(), actions: Self.actions())
        #expect(mounted == false)
    }

    // MARK: 夹具

    private static func descriptor() -> TrayDescriptor {
        TrayDescriptor(
            summary: "3 skills · 1 agents",
            openMainWindowTitle: "打开主窗口",
            scanNowTitle: "立即扫描",
            quitTitle: "退出 AgentKeeper"
        )
    }

    private static func actions() -> TrayActions {
        TrayActions(openMainWindow: {}, scanNow: {})
    }
}

/// mock dlopen 层：句柄/符号表完全可控（托盘降级判定注入点）。
final class MockHandle: Sendable {
    /// 进程内稳定的句柄标识（open/symbol 两步用同一键）。
    let id = Int.random(in: 1..<Int.max)
}

struct MockDynamicLibraryLoader: DynamicLibraryLoader {
    /// path → handle（缺失键 = 打开失败）。
    var handleByPath: [String: MockHandle] = [:]
    /// handle 标识 → 可解析符号名集合。
    var symbolNamesByHandle: [Int: Set<String>] = [:]

    func open(_ path: String) -> UnsafeMutableRawPointer? {
        guard let handle = handleByPath[path] else { return nil }
        return UnsafeMutableRawPointer(bitPattern: handle.id)
    }

    func symbol(_ handle: UnsafeMutableRawPointer, _ name: String) -> UnsafeMutableRawPointer? {
        guard let names = symbolNamesByHandle[Int(bitPattern: handle)] else { return nil }
        return names.contains(name) ? UnsafeMutableRawPointer(bitPattern: 0x1) : nil
    }
}
#endif
