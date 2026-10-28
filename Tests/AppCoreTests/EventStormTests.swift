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
            // 测试窗 600ms：并行套件共享 MainActor，50 次串行 await 的循环在负载下
            // 可能拖过 150ms 防抖窗而合法开出第二窗（物理正确）；600ms 留 4× 余量
            debounceNanos: 600_000_000
        )
        let stormStart = Date()
        for index in 0..<50 {
            await pipeline.onEvent(rootPath: "/tmp/storm-\(index)")
        }
        await pipeline.flushForTesting()
        let stormElapsed = Date().timeIntervalSince(stormStart)
        // 一次重扫（不是 50 次）——功能性断言，必须严格。
        #expect(runnerRuns.value == 1)
        // 挂起护栏（宽松）：150ms 防抖 + 50 事件的理论上限远低于此值；
        // 严格墙钟预算在并行测试负载下会被 MainActor 调度延迟误伤（Intel 实测 6.6s 仍
        // 恰好 1 次重扫），正确性已由 runnerRuns 断言覆盖。
        #expect(stormElapsed < 15.0, "风暴聚合疑似挂起：\(stormElapsed)s")
    }
}
