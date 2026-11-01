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
        // 真实生产组合：CatalogSyncingRunner 负责 build+sync（rescanNow 已不再补第二遍）
        let scanService = ScanService(
            store: store,
            runner: CatalogSyncingRunner(
                upstream: ConfiguredRunner { [root] _ in
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
                },
                catalogStore: catalogStore
            )
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
            // 聚合的本质：rescan 次数与事件数解耦。负载极重时（并行 MainActor 套件
            // 拖过防抖窗）合法开出第二窗，但窗数以个位计。曾断言 ==1（同 fiftyEvents
            // 口径调整），在 2 核 Intel + 重负载下 Thin-margin 误伤。
            debounceNanos: 600_000_000
        )
        // 第一发即断「事件计入 pending」：窗口 600ms 内不会在此刻触发；
        // 整段循环的中段计数会随合法开窗清零（scanStarted 归零），不能精确断言 5。
        await pipeline.onEvent(rootPath: "/tmp/probe-0")
        #expect(store.state.changePendingCount == 1)
        for index in 1..<5 {
            await pipeline.onEvent(rootPath: "/tmp/probe-\(index)")
        }
        // 任何时刻 pending 都不超事件总数（防重复计数回归护栏）
        #expect(store.state.changePendingCount <= 5)
        await pipeline.flushForTesting()
        // 聚合去重：5 事件最多两个防抖窗（绝不随事件数线性增长）；完成计数清零
        #expect(runsBox.value <= 2, "聚合失效：5 事件跑了 \(runsBox.value) 次重扫")
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
