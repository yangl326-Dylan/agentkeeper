#if os(Linux)
import Foundation
import AgentKeeperShared

/// 托盘回调装箱（@convention(c) 不能捕获——user_data 指针经 Unmanaged 往返）。
final class TrayActionBox: @unchecked Sendable {
    let action: @MainActor @Sendable () -> Void
    init(action: @escaping @MainActor @Sendable () -> Void) {
        self.action = action
    }
}

/// AppIndicator 符号表（全部 dlsym 一步到位；任一缺失 → nil 触发降级，
/// 不留半挂载状态。降级判定由单测经 mock loader 覆盖）。
struct AppIndicatorSymbolTable {
    // libayatana-appindicator3
    let appIndicatorNew: @convention(c) (UnsafePointer<CChar>, UnsafePointer<CChar>, Int32) -> UnsafeMutableRawPointer?
    let appIndicatorSetStatus: @convention(c) (UnsafeMutableRawPointer?, Int32) -> Void
    let appIndicatorSetIconFull: @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>, UnsafePointer<CChar>) -> Void
    let appIndicatorSetTitle: @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>) -> Void
    let appIndicatorSetMenu: @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void
    // gtk3
    let gtkMenuNew: @convention(c) () -> UnsafeMutableRawPointer?
    let gtkMenuItemNewWithLabel: @convention(c) (UnsafePointer<CChar>) -> UnsafeMutableRawPointer?
    let gtkMenuShellAppend: @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void
    let gtkWidgetShowAll: @convention(c) (UnsafeMutableRawPointer?) -> Void
    let gtkWidgetSetSensitive: @convention(c) (UnsafeMutableRawPointer?, Bool) -> Void
    // gobject
    let gSignalConnectData: @convention(c) (
        UnsafeMutableRawPointer?,
        UnsafePointer<CChar>,
        @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void,
        UnsafeMutableRawPointer?,
        UnsafeMutableRawPointer?,  // destroy_notify（本实现不使用：Box 应用生命周期保活）
        UInt32
    ) -> UInt

    /// "activate" 回调统一形态：widget 参数忽略，取 user_data Box 跳主线程执行。
    static let activateHandler: @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void = { _, userData in
        guard let userData else { return }
        let box = Unmanaged<TrayActionBox>.fromOpaque(userData).takeUnretainedValue()
        Task { @MainActor in
            box.action()
        }
    }

    /// 库句柄 + 全符号解析；任一步失败返回 nil（降级判定单测走这里）。
    static func resolve(
        loader: any DynamicLibraryLoader,
        appIndicatorPath: String = "libayatana-appindicator3.so.1",
        gtkPath: String = "libgtk-3.so.0",
        gobjectPath: String = "libgobject-2.0.so.0"
    ) -> Self? {
        guard let appIndicator = loader.open(appIndicatorPath),
              let gtk = loader.open(gtkPath),
              let gobject = loader.open(gobjectPath)
        else { return nil }

        guard let pNew = loader.symbol(appIndicator, "app_indicator_new"),
              let pSetStatus = loader.symbol(appIndicator, "app_indicator_set_status"),
              let pSetIconFull = loader.symbol(appIndicator, "app_indicator_set_icon_full"),
              let pSetTitle = loader.symbol(appIndicator, "app_indicator_set_title"),
              let pSetMenu = loader.symbol(appIndicator, "app_indicator_set_menu"),
              let pMenuNew = loader.symbol(gtk, "gtk_menu_new"),
              let pItemNew = loader.symbol(gtk, "gtk_menu_item_new_with_label"),
              let pShellAppend = loader.symbol(gtk, "gtk_menu_shell_append"),
              let pShowAll = loader.symbol(gtk, "gtk_widget_show_all"),
              let pSetSensitive = loader.symbol(gtk, "gtk_widget_set_sensitive"),
              let pSignalConnect = loader.symbol(gobject, "g_signal_connect_data")
        else { return nil }

        return Self(
            appIndicatorNew: unsafeBitCast(pNew, to: (@convention(c) (UnsafePointer<CChar>, UnsafePointer<CChar>, Int32) -> UnsafeMutableRawPointer?).self),
            appIndicatorSetStatus: unsafeBitCast(pSetStatus, to: (@convention(c) (UnsafeMutableRawPointer?, Int32) -> Void).self),
            appIndicatorSetIconFull: unsafeBitCast(pSetIconFull, to: (@convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>, UnsafePointer<CChar>) -> Void).self),
            appIndicatorSetTitle: unsafeBitCast(pSetTitle, to: (@convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>) -> Void).self),
            appIndicatorSetMenu: unsafeBitCast(pSetMenu, to: (@convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void).self),
            gtkMenuNew: unsafeBitCast(pMenuNew, to: (@convention(c) () -> UnsafeMutableRawPointer?).self),
            gtkMenuItemNewWithLabel: unsafeBitCast(pItemNew, to: (@convention(c) (UnsafePointer<CChar>) -> UnsafeMutableRawPointer?).self),
            gtkMenuShellAppend: unsafeBitCast(pShellAppend, to: (@convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void).self),
            gtkWidgetShowAll: unsafeBitCast(pShowAll, to: (@convention(c) (UnsafeMutableRawPointer?) -> Void).self),
            gtkWidgetSetSensitive: unsafeBitCast(pSetSensitive, to: (@convention(c) (UnsafeMutableRawPointer?, Bool) -> Void).self),
            gSignalConnectData: unsafeBitCast(pSignalConnect, to: (@convention(c) (
                UnsafeMutableRawPointer?,
                UnsafePointer<CChar>,
                @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void,
                UnsafeMutableRawPointer?,
                UnsafeMutableRawPointer?,
                UInt32
            ) -> UInt).self)
        )
    }
}

/// AppIndicator 托盘（dlopen 版，零 C 目标依赖）。
/// 全部符号经 `DynamicLibraryLoader` 注入：任一步失败即返回 false 触发界内降级提示。
/// 菜单：摘要行（不可点）→ 打开主窗口 → 立即扫描 → 退出。
/// （成对文件：macOS 侧 MenuBarExtra/MenuBarPanel.swift。）
final class AppIndicatorTray: @unchecked Sendable {
    private let stateLock = NSLock()
    private var indicator: UnsafeMutableRawPointer?
    /// 菜单项 user_data 的 +1 指针（passRetained 所得；托盘生命周期内保活，unmount 时逐一释放）。
    private var retainedActionPointers: [UnsafeMutableRawPointer] = []

    /// 挂载托盘。任一 dlopen/dlsym/菜单构建步骤失败 → false（不抛半成品状态）。
    @discardableResult
    func mount(
        descriptor: TrayDescriptor,
        iconName: String,
        actions: TrayActions,
        quit: @escaping @MainActor @Sendable () -> Void,
        loader: any DynamicLibraryLoader
    ) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard indicator == nil else { return true } // 幂等：已挂载视为成功

        guard let s = AppIndicatorSymbolTable.resolve(loader: loader) else { return false }
        guard let menu = s.gtkMenuNew() else { return false }

        // 摘要行（不可点）
        guard appendItem(descriptor.summary, sensitive: false, action: nil, to: menu, s) else { return false }
        // 打开主窗口 / 立即扫描 / 退出
        guard appendItem(descriptor.openMainWindowTitle, sensitive: true, action: actions.openMainWindow, to: menu, s),
              appendItem(descriptor.scanNowTitle, sensitive: true, action: actions.scanNow, to: menu, s),
              appendItem(descriptor.quitTitle, sensitive: true, action: quit, to: menu, s)
        else { return false }

        s.gtkWidgetShowAll(menu)

        // 指示器：id 固定（DBus 唯一）；category 1 = Application Status；status 1 = Active
        guard let built = s.appIndicatorNew("agentkeeper-tray", iconName, 1) else { return false }
        s.appIndicatorSetStatus(built, 1)
        s.appIndicatorSetIconFull(built, iconName, "AgentKeeper")
        s.appIndicatorSetTitle(built, "AgentKeeper")
        s.appIndicatorSetMenu(built, menu)

        indicator = built
        return true
    }

    func unmount() {
        stateLock.lock()
        defer { stateLock.unlock() }
        // AppIndicator 无显式销毁符号接入：set_status 0=Passive 即隐藏（托盘对用户消失）；
        // v1 真正的清理依赖应用退出。符号表不可再得则静默——进程即将退出。
        if indicator != nil, let s = AppIndicatorSymbolTable.resolve(loader: DlDynamicLibraryLoader()) {
            s.appIndicatorSetStatus(indicator, 0)
        }
        indicator = nil
        for pointer in retainedActionPointers {
            Unmanaged<TrayActionBox>.fromOpaque(pointer).release()
        }
        retainedActionPointers = []
    }

    /// 构建菜单项并追加；带 action 时连接 "activate" 信号（Box 保活登记）。
    /// 任一构建步骤失败返回 false。
    private func appendItem(
        _ label: String,
        sensitive: Bool,
        action: (@MainActor @Sendable () -> Void)?,
        to menu: UnsafeMutableRawPointer?,
        _ s: AppIndicatorSymbolTable
    ) -> Bool {
        guard let item = s.gtkMenuItemNewWithLabel(label) else { return false }
        s.gtkMenuShellAppend(menu, item)
        s.gtkWidgetSetSensitive(item, sensitive)
        if let action {
            let box = TrayActionBox(action: action)
            let userData = Unmanaged.passRetained(box).toOpaque()
            retainedActionPointers.append(userData)
            _ = s.gSignalConnectData(item, "activate", AppIndicatorSymbolTable.activateHandler, userData, nil, 0)
        }
        return true
    }
}
#endif
