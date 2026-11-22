#if os(Linux)
import Foundation

/// dlopen/dlsym 注入层：托盘挂载（AppIndicator/GTK3 dlopen 全走此协议），
/// 单测以 mock 实现覆盖降级判定（真机路径不进单测——不可控系统库）。
/// 句柄类型用 `UnsafeMutableRawPointer`：Linux 的 dlopen 返回该类型
/// （Darwin 的 OpaquePointer 在 glibc 头文件里不可互换）。
public protocol DynamicLibraryLoader: Sendable {
    /// 打开动态库；失败返回 nil。
    func open(_ path: String) -> UnsafeMutableRawPointer?

    /// 取符号地址；缺失返回 nil。
    func symbol(_ handle: UnsafeMutableRawPointer, _ name: String) -> UnsafeMutableRawPointer?
}

/// 真实现：dlopen/dlsym 直通。句柄永不 dlclose（托盘存活与应用同生命周期，
/// 提前关闭会悬空全部函数指针——有意省略）。
public struct DlDynamicLibraryLoader: DynamicLibraryLoader {
    public init() {}

    public func open(_ path: String) -> UnsafeMutableRawPointer? {
        dlopen(path, RTLD_NOW | RTLD_GLOBAL)
    }

    public func symbol(_ handle: UnsafeMutableRawPointer, _ name: String) -> UnsafeMutableRawPointer? {
        dlsym(handle, name)
    }
}
#endif
