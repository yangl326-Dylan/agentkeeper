#if os(Linux)
import Foundation
import AgentKeeperShared
import AppCore

/// Linux 动效策略（成对文件：Sources/AgentKeeperUI/MotionPolicy.swift）。
/// SCUI v0.11 无 SwiftUI `Animation` 等价 API（PoC/实装双重确认）——
/// 减少动效的语义落点：关闭扫描呼吸/旋转指示的装饰性动效（静态文案 + 静态圆点），
/// 布局切换本就即时呈现（SCUI 无过渡动画），状态语义不打折。
public struct LinuxMotionPolicy: Hashable, Sendable {
    public var reduceMotion: Bool

    public init(reduceMotion: Bool) {
        self.reduceMotion = reduceMotion
    }

    /// 扫描进行中是否展示旋转指示（ProgressView spinner）。
    /// 减少动效 → 静态「◐」符号 + 文案（呼吸/旋转属纯装饰）。
    public var showsScanSpinner: Bool { !reduceMotion }
}

/// Reduce Motion 决策（对齐 macOS MotionPolicy 构造语义）：
/// 用户设置覆盖优先，未覆盖时经 PlatformAdapter 采系统辅助功能值。
@MainActor
public func linuxMotionPolicy(for env: AppEnvironment) -> LinuxMotionPolicy {
    LinuxMotionPolicy(reduceMotion: env.settings.effectiveReduceMotion(
        accessibility: env.adapter.isReduceMotionEnabled
    ))
}

/// 状态条文案构建（纯函数；成对文件：RootView.swift 的 ScanStatusText——
/// 任务 2.4 共享 VM 剥离暂缓，两侧引用同一 L10n 键，文案语义逐字对齐）。
@MainActor
public enum LinuxScanStatusText {
    private static let clock = DateFormatter()
    private static let compactClock = DateFormatter()

    public static func clockText(_ date: Date) -> String {
        clock.dateFormat = "HH:mm:ss"
        return clock.string(from: date)
    }

    public static func build(scan: ScanPhaseState, skillsCount: Int, l10n: L10n) -> String {
        switch scan.phase {
        case .idle: return l10n.stripIdle
        case .running: return l10n.stripRunning
        case .complete:
            let time = scan.lastCompletedAt.map { clockText($0) } ?? "--:--:--"
            return l10n.stripDone(agents: scan.agentCount, skills: skillsCount, time: time)
        case .failed: return l10n.stripFailedDetail(scan.failureMessage ?? "--")
        }
    }

    /// 紧凑版（窄侧栏防换行）：保留 skill 数与时分，舍弃秒与 agent 数。
    public static func compact(scan: ScanPhaseState, skillsCount: Int, l10n: L10n) -> String {
        switch scan.phase {
        case .idle: return l10n.stripIdle
        case .running: return l10n.stripRunningCompact
        case .complete:
            compactClock.dateFormat = "HH:mm"
            let time = scan.lastCompletedAt.map { compactClock.string(from: $0) } ?? "--:--"
            return "\(skillsCount) skills · \(time)"
        case .failed: return l10n.stripFailed
        }
    }

    /// 扫描状态 → 颜色语义键（对齐 RootView 的 ScanStatusStrip.tint）。
    public static func colorKey(for scan: ScanPhaseState) -> String {
        switch scan.phase {
        case .idle: "gray"
        case .running: "blue"
        case .complete: "green"
        case .failed: "red"
        }
    }
}

/// 托盘降级提示文案（Linux 界内提示专用——Shared L10n 无此键，且 AppCore
/// 属只读边界：文案以解析语言双语文案落在本栈）。
public func trayUnavailableText(_ l10n: L10n) -> String {
    switch l10n.lang {
    case .zhHans: "托盘不可用（未检测到 AppIndicator）——功能不受影响，可从主窗口操作"
    case .english: "Tray unavailable (AppIndicator not found) — all features remain available in the main window"
    }
}
#endif
