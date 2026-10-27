import Foundation
import Testing
import DomainKit
@testable import InfraKit

@Suite struct FileMonitorProtocolTests {
    @Test func fakeMonitorDrivesEventThroughConsumer() async {
        let received = ReceiveBox()
        let monitor = FakeMonitor { event in
            await MainActor.run {
                received.record(event.rootPath)
            }
        }
        let root = URL(fileURLWithPath: "/tmp/watched")
        await monitor.start(watchingRoots: [root])
        await monitor.emit(rootPath: root)
        #expect(received.paths.count == 1)
        #expect(received.paths[0] == root.path)
        await monitor.stopAll()
        let rootsAfterStop = await monitor.watchedRoots
        #expect(rootsAfterStop.isEmpty)
    }
}

@Suite struct FSEventMonitorIntegrationTests {
    @Test func realFSDirectoryWriteProducesAggregatedEvent() async throws {
        let home = makeFakeHome(files: ["watched/readme.md"])
        defer { cleanup(home) }
        let root = home.appendingPathComponent("watched", isDirectory: true)

        let received = ReceiveBox()
        let monitor = FSEventMonitor(latencySeconds: 0.2) { event in
            await MainActor.run {
                received.record(event.rootPath)
            }
        }
        await monitor.start(watchingRoots: [root])
        defer { Task { await monitor.stopAll() } }

        // 实际写入触发 FSEvents
        let probe = root.appendingPathComponent("probe-\(UUID().uuidString).txt")
        try "payload".write(to: probe, atomically: true, encoding: .utf8)

        for _ in 0..<50 {
            if !received.paths.isEmpty { break }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        #expect(received.paths.contains { $0.contains("/watched/") })
    }
}

final class ReceiveBox: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var paths: [String] = []
    func record(_ path: String) {
        lock.lock()
        defer { lock.unlock() }
        paths.append(path)
    }
}
