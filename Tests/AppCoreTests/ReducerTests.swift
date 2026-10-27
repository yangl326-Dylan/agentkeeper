import Foundation
import Testing
import DomainKit
@testable import AppCore

// MARK: - Reducer 纯函数状态机

@Suite struct ScannerReducerTests {
    @Test func initialStateIsIdle() {
        let state = AppState.initial
        #expect(state.scan.phase == .idle)
        #expect(state.agents.isEmpty)
    }

    @Test func scanStartedTransitionsToRunning() {
        var state = AppState.initial
        state.apply(.scanStarted)
        #expect(state.scan.phase == .running)
        #expect(state.scan.startedAt != nil)
    }

    @Test func scanCompletedStoresReportSummary() {
        var state = AppState.initial
        state.apply(.scanStarted)
        var report = ScanReport.empty
        report.add(
            agent: Agent(
                id: "claude-code",
                name: "Claude Code",
                installState: .installed(configDirectory: nil)),
            diagnostics: []
        )
        state.apply(.scanCompleted(report))
        #expect(state.scan.phase == .complete)
        #expect(state.agents.count == 1)
        #expect(state.scan.agentCount == 1)
        #expect(state.scan.diagnosticCount == 0)
        #expect(state.scan.lastCompletedAt != nil)
    }

    @Test func scanFailedRecordsMessage() {
        var state = AppState.initial
        state.apply(.scanStarted)
        state.apply(.scanFailed(message: "磁盘忙"))
        #expect(state.scan.phase == .failed)
        #expect(state.scan.failureMessage == "磁盘忙")
        // 失败不丢已有 agent 数据
        #expect(state.agents.isEmpty)
    }

    @Test func externalChangeMarksChangePending() {
        var state = AppState.initial
        state.apply(.externalChangeDetected(paths: ["/Users/x/.claude/skills/a"]))
        #expect(state.changePendingCount == 1)
    }
}

// MARK: - AppUpdateStream 收发

@Suite struct AppUpdateStreamTests {
    @Test func subscribersReceiveUpdates() async throws {
        let stream = AppUpdateStream()
        var iterator = await stream.subscribe().makeAsyncIterator()
        await stream.send(.stateDidUpdate)
        let received = await iterator.next()
        #expect(received == .stateDidUpdate)
    }

    @Test func multipleSubscribersEachReceive() async {
        let stream = AppUpdateStream()
        var it1 = await stream.subscribe().makeAsyncIterator()
        var it2 = await stream.subscribe().makeAsyncIterator()
        await stream.send(.stateDidUpdate)
        #expect(await it1.next() == .stateDidUpdate)
        #expect(await it2.next() == .stateDidUpdate)
    }
}

// MARK: - AppStore 端到端（reducer + 广播）

@Suite @MainActor struct AppStoreTests {
    @Test func dispatchingActionUpdatesStateAndBroadcasts() async {
        let store = AppStore()
        var iterator = await store.updates.subscribe().makeAsyncIterator()
        await store.dispatch(.scanStarted)
        #expect(store.state.scan.phase == .running)
        _ = await iterator.next()
    }
}
