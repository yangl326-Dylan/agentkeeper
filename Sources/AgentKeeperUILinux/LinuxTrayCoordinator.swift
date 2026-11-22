#if os(Linux)
import Foundation
import AgentKeeperShared

/// 托盘「打开主窗口」动作的线程安全登记处：托盘挂载在视图上下文（能拿到
/// SCUI 的 openWindow 环境动作）完成，而动作触发来自 GTK 回调线程——
/// 经此 Box 中转（@Sendable 闭包无法直接捕获非 Sendable 的 OpenWindowAction）。
final class LinuxTrayCoordinator: @unchecked Sendable {
    static let shared = LinuxTrayCoordinator()

    private let lock = NSLock()
    private var openMainWindowAction: (@MainActor () -> Void)?

    /// 视图上下文登记（通常传 { openWindow(id: "main") }）。
    func registerOpenMainWindow(_ action: @escaping @MainActor () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        openMainWindowAction = action
    }

    /// 托盘菜单触发：若已登记则跳主线程执行；未登记时静默（托盘先于视图挂载的窗口期）。
    func activateMainWindow() {
        lock.lock()
        let action = openMainWindowAction
        lock.unlock()
        guard let action else { return }
        Task { @MainActor in
            action()
        }
    }
}
#endif
