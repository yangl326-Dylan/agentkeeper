import Foundation
import DomainKit
@testable import InfraKit

/// 队列驱动 fake monitor：注入消费端做协议级测试。
public actor FakeMonitor: FileMonitoring {
    private let handler: @Sendable (FileChangeEvent) async -> Void
    private var started: Bool = false
    public private(set) var watchedRoots: [URL]

    public init(handler: @escaping @Sendable (FileChangeEvent) async -> Void) {
        self.handler = handler
        self.watchedRoots = []
    }

    public func start(watchingRoots: [URL]) async {
        self.watchedRoots = watchingRoots
        started = true
    }

    public func stopAll() async {
        started = false
        watchedRoots = []
    }

    /// 测试驱动：模拟一次聚合事件。
    public func emit(rootPath: URL) async {
        await handler(FileChangeEvent(rootPath: rootPath.path))
    }
}
