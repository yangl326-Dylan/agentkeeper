import Foundation
import Testing
import DomainKit
import InfraKit
@testable import AppCore

/// 风暴压测（7.2 的事件侧）。
@Suite @MainActor struct EventStormTests {
    @Test func fiftyEventsAggregateIntoSingleRescan() async {
        let store = AppStore()
        let catalogStore = CatalogStore()
        let runnerRuns = IntegerBox()
        let scanService = ScanService(
            store: store,
            runner: ConfiguredRunner { _ in
                runnerRuns.increment()
                return ScanReport.empty
            }
        )
        let pipeline = ChangePipeline(
            store: store,
            catalogStore: catalogStore,
            scanService: scanService,
            debounceNanos: 150_000_000
        )
        let stormStart = Date()
        for index in 0..<50 {
            await pipeline.onEvent(rootPath: "/tmp/storm-\(index)")
        }
        await pipeline.flushForTesting()
        let stormElapsed = Date().timeIntervalSince(stormStart)
        // 一次重扫（不是 50 次）；防抖窗口正常收束
        #expect(runnerRuns.value == 1)
        #expect(stormElapsed < 2.0, "风暴聚合收束应在 2s 内，实际 \(stormElapsed)s")
    }
}
