import Foundation
import Testing
import DomainKit
import InfraKit
@testable import AppCore

/// AppCore 测试本地 fake monitor（与 InfraKitTests 的互不干扰）。
public actor LocalFakeMonitor: FileMonitoring {
    private let handler: @Sendable (FileChangeEvent) async -> Void
    public private(set) var watchedRoots: [URL]

    public init(handler: @escaping @Sendable (FileChangeEvent) async -> Void) {
        self.handler = handler
        self.watchedRoots = []
    }

    public func start(watchingRoots: [URL]) async {
        self.watchedRoots = watchingRoots
    }

    public func stopAll() async {
        watchedRoots = []
    }

    public func emit(rootPath: URL) async {
        await handler(FileChangeEvent(rootPath: rootPath.path))
    }
}

@Suite @MainActor struct ChangePipelineTests {
    @Test func externalChangeEventEndsWithRefreshedCatalog() async throws {
        let home = makeFakeHome(
            files: [".claude/skills/alpha/SKILL.md"],
            fileContents: [
                ".claude/skills/alpha/SKILL.md": "---\nname: alpha\ndescription: 测试 skill\n---\nA",
            ]
        )
        defer { cleanup(home) }
        let root = home.appendingPathComponent(".claude/skills", isDirectory: true)

        let store = AppStore()
        let catalogStore = CatalogStore()
        let scanService = ScanService(
            store: store,
            runner: ConfiguredRunner { [root] _ in
                var report = ScanReport.empty
                report.add(
                    agent: Agent(
                        id: "claude-code",
                        name: "Claude Code",
                        installState: .installed(configDirectory: nil),
                        skillRoots: [SkillRoot(path: root, owners: ["claude-code"], level: .user)]
                    ),
                    diagnostics: []
                )
                return report
            }
        )
        let pipeline = ChangePipeline(
            store: store,
            catalogStore: catalogStore,
            scanService: scanService,
            debounceNanos: 50_000_000
        )

        let monitor = LocalFakeMonitor { [weak pipeline] (event: FileChangeEvent) in
            await pipeline?.onEvent(rootPath: event.rootPath)
        }
        await pipeline.attach(monitor: monitor)

        await monitor.emit(rootPath: root)
        await pipeline.flushForTesting()

        #expect(catalogStore.current.count == 1)
        #expect(catalogStore.current[0].name == "alpha")
        #expect(catalogStore.current[0].scope == .agentOnly(agentID: "claude-code"))
    }

    @Test func changePendingResetsAfterCompletedRescan() async {
        let store = AppStore()
        let catalogStore = CatalogStore()
        let scanService = ScanService(
            store: store,
            runner: ConfiguredRunner { _ in ScanReport.empty }
        )
        let pipeline = ChangePipeline(
            store: store,
            catalogStore: catalogStore,
            scanService: scanService,
            debounceNanos: 20_000_000
        )

        await pipeline.onEvent(rootPath: "/tmp/pending-probe")
        #expect(store.state.changePendingCount == 1)

        await pipeline.flushForTesting()
        #expect(store.state.scan.phase == .complete)
        #expect(store.state.changePendingCount == 0)
    }

    @Test func rapidEventsAggregateIntoSingleRescan() async {
        let store = AppStore()
        let catalogStore = CatalogStore()
        let runsBox = IntegerBox()
        let scanService = ScanService(
            store: store,
            runner: ConfiguredRunner { _ in
                runsBox.increment()
                return ScanReport.empty
            }
        )
        let pipeline = ChangePipeline(
            store: store,
            catalogStore: catalogStore,
            scanService: scanService,
            // 测试窗 600ms：并行套件共享 MainActor，串行 await 循环在负载下可能拖过
            // 150ms 防抖窗而合法开出第二窗（物理正确）；600ms 留 4× 余量
            debounceNanos: 600_000_000
        )
        for index in 0..<5 {
            await pipeline.onEvent(rootPath: "/tmp/probe-\(index)")
        }
        // 五个事件全部计入 pending；重扫尚未跑（debounce 中）
        #expect(store.state.changePendingCount == 5)
        await pipeline.flushForTesting()
        // 聚合去重后只跑一次重扫；完成计数清零
        #expect(runsBox.value == 1)
        #expect(store.state.changePendingCount == 0)
    }
}

final class IntegerBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value_ = 0
    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return value_
    }
    func increment() {
        lock.lock()
        defer { lock.unlock() }
        value_ += 1
    }
}
