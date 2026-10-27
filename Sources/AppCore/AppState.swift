import Foundation
import DomainKit
import InfraKit

// MARK: - AppAction

/// 触发状态变更的动作（来自 UI、后台服务、外部事件）。
public enum AppAction: Sendable, Equatable {
    // 扫描
    case scanStarted
    case scanCompleted(ScanReport)
    case scanFailed(message: String)

    // 操作（skill-lifecycle）
    case operationStarted(skillID: String, direction: OperationDirection)
    case operationCompleted(skillID: String, direction: OperationDirection)
    case operationFailed(skillID: String, direction: OperationDirection, message: String)

    // 外部变更（FSEvents 聚合后）
    case externalChangeDetected(paths: [String])
}

// MARK: - AppState

/// 扫描流程状态。
public struct ScanPhaseState: Sendable, Equatable {
    public enum Phase: Sendable, Equatable { case idle, running, complete, failed }

    public init() {}

    public var phase: Phase = .idle
    public var startedAt: Date?
    public var lastCompletedAt: Date?
    public var agentCount: Int = 0
    public var diagnosticCount: Int = 0
    public var failureMessage: String?
}

/// 操作流程状态（进行中/完成/失败语义，UI 冲突面板按 failureMessage 展示）。
public struct OperationPhaseState: Sendable, Equatable {
    public struct InFlightKey: Sendable, Equatable {
        public var skillID: String
        public var direction: OperationDirection
        public init(skillID: String, direction: OperationDirection) {
            self.skillID = skillID
            self.direction = direction
        }
    }

    public init() {}

    public var inFlight: InFlightKey?
    public var failureMessage: String?
    public var lastCompletedAt: Date?
}

/// 应用全局状态（只读快照下发 UI，不持有可变共享引用）。
public struct AppState: Sendable, Equatable {
    public var scan: ScanPhaseState
    public var agents: [Agent]
    /// 已接收但尚未处理的目录级变更数（增量重扫调度由后续任务消费）。
    public var changePendingCount: Int
    public var operation: OperationPhaseState

    public static let initial = AppState(
        scan: ScanPhaseState(),
        agents: [],
        changePendingCount: 0
    )

    public init(
        scan: ScanPhaseState = ScanPhaseState(),
        agents: [Agent] = [],
        changePendingCount: Int = 0,
        operation: OperationPhaseState = OperationPhaseState()
    ) {
        self.scan = scan
        self.agents = agents
        self.changePendingCount = changePendingCount
        self.operation = operation
    }
}

// MARK: - Reducer

extension AppState {
    /// 纯函数状态推进：所有状态变更必须经由本方法（单点入口，防 UI 状态涣散）。
    public mutating func apply(_ action: AppAction) {
        switch action {
        case .scanStarted:
            scan = ScanPhaseState()
            scan.phase = .running
            scan.startedAt = Date()

        case let .scanCompleted(report):
            agents = report.agents
            scan.phase = .complete
            scan.lastCompletedAt = Date()
            scan.agentCount = report.agents.count
            scan.diagnosticCount = report.diagnostics.count
            changePendingCount = 0

        case let .scanFailed(message):
            scan.phase = .failed
            scan.failureMessage = message

        case let .externalChangeDetected(paths):
            changePendingCount += paths.count
            scan.agentCount = agents.count

        case let .operationStarted(skillID, direction):
            operation.inFlight = OperationPhaseState.InFlightKey(skillID: skillID, direction: direction)
            operation.failureMessage = nil

        case let .operationCompleted(skillID, direction):
            _ = skillID
            _ = direction
            operation.inFlight = nil
            operation.failureMessage = nil
            operation.lastCompletedAt = Date()

        case let .operationFailed(skillID, direction, message):
            _ = skillID
            _ = direction
            operation.inFlight = nil
            operation.failureMessage = message
        }
    }
}

// MARK: - AppUpdate 广播

/// 下发给 Presentation 的更新事件。
public enum AppUpdate: Sendable, Equatable {
    case stateDidUpdate
}
