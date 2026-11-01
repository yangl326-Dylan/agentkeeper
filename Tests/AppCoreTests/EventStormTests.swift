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
            // 聚合的本质：rescan 次数与事件数解耦。负载极重时（并行 MainActor 套件
            // 拖过防抖窗）合法开出第二窗，但窗数以个位计、与事件数完全无关。
            // 曾断言 ==1，在 2 核 Intel + 重 UI 探针负载下 Thin-margin 误伤（实证 2 窗）。
            debounceNanos: 600_000_000
        )
        let stormStart = Date()
        for index in 0..<50 {
            await pipeline.onEvent(rootPath: "/tmp/storm-\(index)")
        }
        await pipeline.flushForTesting()
        let stormElapsed = Date().timeIntervalSince(stormStart)
        // 聚合护栏：50 次事件最多两个防抖窗（绝不随事件数线性增长）——功能性上限。
        #expect(runnerRuns.value <= 2, "聚合失效：50 事件跑了 \(runnerRuns.value) 次重扫")
        // 挂起护栏（宽松）：150ms 防抖 + 50 事件的理论上限远低于此值；
        // 严格墙钟预算在并行测试负载下会被 MainActor 调度延迟误伤（Intel 实测 6.6s 仍
        // 恰好 1 次重扫），正确性已由 runnerRuns 断言覆盖。
        #expect(stormElapsed < 15.0, "风暴聚合疑似挂起：\(stormElapsed)s")
    }
}
