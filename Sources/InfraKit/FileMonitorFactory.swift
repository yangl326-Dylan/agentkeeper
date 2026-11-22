import Foundation
import DomainKit

// MARK: - 文件监听平台工厂（平台适配点，唯一允许 os 分派的位置之一）

/// 按平台构造文件监听器：macOS=FSEvents，Linux=inotify。
/// 回调语义双平台一致：整批路径数组一次交割，消费方自行聚合/过滤。
public enum FileMonitorFactory {
    /// 构造平台原生监听器；`handler` 为空批次语义由实现保证（只在有内容时送达）。
    public static func make(
        latencySeconds: Double,
        handler: @escaping @Sendable ([String]) async -> Void
    ) -> (any FileMonitoring)? {
        #if os(macOS)
        return FSEventMonitor(latencySeconds: latencySeconds, handler: handler)
        #elseif os(Linux)
        return InotifyMonitor(latencySeconds: latencySeconds, handler: handler)
        #else
        return nil
        #endif
    }
}
