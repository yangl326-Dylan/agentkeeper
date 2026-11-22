#if os(Linux)
import Foundation
import Testing
@testable import InfraKit

/// InotifyMonitor 集成测试：真实文件系统事件 → inotify → 去抖聚合 → 整批送达。
/// 与 FSEventMonitorTests.swift（macOS）对称，仅 Linux 编译。
@Suite struct InotifyMonitorIntegrationTests {

    @Test func writeModifyDeleteDeliverAggregatedPaths() async throws {
        let root = try Self.makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let collector = InotifyEventCollector()
        let monitor = InotifyMonitor(latencySeconds: 0.2) { paths in
            collector.record(paths)
        }
        await monitor.start(watchingRoots: [root])
        defer { Task { await monitor.stopAll() } }

        // 触发：写、改、删各一枚，外加子目录里的文件
        let probe = root.appendingPathComponent("probe-\(UUID().uuidString).txt")
        try "v1".write(to: probe, atomically: true, encoding: .utf8)
        try "v2".write(to: probe, atomically: true, encoding: .utf8)   // 修改
        let sub = root.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        let subProbe = sub.appendingPathComponent("inner.txt")
        try "inner".write(to: subProbe, atomically: true, encoding: .utf8)
        try FileManager.default.removeItem(at: probe)                   // 删除

        let sawProbe = await Self.waitUntil(timeoutSeconds: 5) { collector.contains(probe.path) }
        #expect(sawProbe, "5s 内未收到 probe 事件，实际批次：\(collector.batchesDescription)")
        let sawInner = await Self.waitUntil(timeoutSeconds: 5) { collector.contains(subProbe.path) }
        #expect(sawInner, "5s 内未收到子目录文件事件，实际批次：\(collector.batchesDescription)")
    }

    @Test func createdSubdirectoryIsWatchedDynamically() async throws {
        let root = try Self.makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let collector = InotifyEventCollector()
        let monitor = InotifyMonitor(latencySeconds: 0.2) { paths in
            collector.record(paths)
        }
        await monitor.start(watchingRoots: [root])
        defer { Task { await monitor.stopAll() } }

        // start 之后再建子目录 → 只有动态补 watch 生效才能看见其内部文件
        let sub = root.appendingPathComponent("late-sub", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try await Task.sleep(nanoseconds: 300_000_000)   // 给补 watch 留出处理窗口
        let inner = sub.appendingPathComponent("late-inner.txt")
        try "x".write(to: inner, atomically: true, encoding: .utf8)

        let sawInner = await Self.waitUntil(timeoutSeconds: 5) { collector.contains(inner.path) }
        #expect(sawInner, "动态补 watch 未生效：未收到 \(inner.path)，实际批次：\(collector.batchesDescription)")
    }

    @Test func stopAllStopsDelivery() async throws {
        let root = try Self.makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let collector = InotifyEventCollector()
        let monitor = InotifyMonitor(latencySeconds: 0.2) { paths in
            collector.record(paths)
        }
        await monitor.start(watchingRoots: [root])
        defer { Task { await monitor.stopAll() } }

        let before = root.appendingPathComponent("before.txt")
        try "x".write(to: before, atomically: true, encoding: .utf8)
        let delivered = await Self.waitUntil(timeoutSeconds: 5) { collector.eventCount > 0 }
        #expect(delivered, "stop 前的写入未送达，实际批次：\(collector.batchesDescription)")

        await monitor.stopAll()
        let countAtStop = collector.eventCount

        // 越过一个完整 flush 窗口后再写入，不应再送达
        try await Task.sleep(nanoseconds: 1_000_000_000)
        let after = root.appendingPathComponent("after.txt")
        try "y".write(to: after, atomically: true, encoding: .utf8)
        try await Task.sleep(nanoseconds: 1_000_000_000)
        #expect(
            collector.eventCount == countAtStop,
            "stopAll 后仍收到事件（新增 \(collector.eventCount - countAtStop) 个批次），实际批次：\(collector.batchesDescription)"
        )
    }

    // MARK: - 辅助

    /// 轮询等待条件成立（默认 ~5s 超时），返回是否等到。
    private static func waitUntil(timeoutSeconds: Double, _ condition: @escaping () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return condition()
    }

    /// 在系统临时目录下建独立的 UUID 根目录（测试自身负责清理）。
    private static func makeTempRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ak-inotify-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}

/// 线程安全收集器：整批记录 handler 送达的路径（供断言与失败上下文）。
final class InotifyEventCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var batches: [[String]] = []

    /// 累计送达的批次个数。
    var eventCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return batches.count
    }

    func record(_ batch: [String]) {
        lock.lock()
        defer { lock.unlock() }
        batches.append(batch)
    }

    /// 任一批次包含该路径即命中。
    func contains(_ path: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return batches.contains { $0.contains(path) }
    }

    /// 失败上下文：全部批次拼接展示。
    var batchesDescription: String {
        lock.lock()
        defer { lock.unlock() }
        return batches.map { "[\($0.joined(separator: ", "))]" }.joined(separator: " ")
    }
}

#endif
