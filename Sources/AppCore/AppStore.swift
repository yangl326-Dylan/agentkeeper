import Foundation
import DomainKit

/// 状态更新的广播通道：AppCore 单入口发送，Presentation 多订阅者接收。
public actor AppUpdateStream {
    private var continuations: [UUID: AsyncStream<AppUpdate>.Continuation] = [:]

    public init() {}

    public func subscribe() -> AsyncStream<AppUpdate> {
        let id = UUID()
        let stream = AsyncStream<AppUpdate> { continuation in
            continuation.onTermination = { [weak self] _ in
                Task { await self?.unsubscribe(id) }
            }
            Task { self.register(id: id, continuation: continuation) }
        }
        return stream
    }

    private func register(id: UUID, continuation: AsyncStream<AppUpdate>.Continuation) {
        continuations[id] = continuation
    }

    public func send(_ update: AppUpdate) {
        for continuation in continuations.values {
            continuation.yield(update)
        }
    }

    private func unsubscribe(_ id: UUID) {
        continuations[id] = nil
    }
}

/// AppCore 门面：dispatch 单一入口（reducer + 广播），UI 侧 @MainActor 观察。
@MainActor
@Observable
public final class AppStore {
    public private(set) var state: AppState
    public let updates: AppUpdateStream

    public init(updates: AppUpdateStream = AppUpdateStream(), initialState: AppState = .initial) {
        self.updates = updates
        self.state = initialState
    }

    public func dispatch(_ action: AppAction) async {
        state.apply(action)
        await updates.send(.stateDidUpdate)
    }
}
