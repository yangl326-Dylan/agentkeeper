import Foundation

/// 状态语义 token（spec app-ui「风险与状态语义清晰」）。
public enum StatusToken: Hashable, CaseIterable, Sendable {
    case enabled        // 已启用
    case disabled       // 已禁用
    case changed        // 变更（尚未复审）
    case conflict       // 冲突（需处理）
    case permissionDenied // 权限受限（需处理）
    case unrecognized   // 无法识别
}

/// 状态 → 颜色 / 图标 / 悬停释义 的唯一映射（红=需处理，琥珀=注意，绿=正常）。
public struct StatusSemantics: Hashable, Sendable {
    /// 颜色语义键："green" | "amber" | "red"。
    public var colorKey: String
    /// SF Symbols 图标名。
    public var symbol: String
    /// 悬停释义（辅助功能朗读也用它）。
    public var explanation: String

    public init(colorKey: String, symbol: String, explanation: String) {
        self.colorKey = colorKey
        self.symbol = symbol
        self.explanation = explanation
    }

    public static func resolve(_ token: StatusToken) -> StatusSemantics {
        switch token {
        case .enabled:
            StatusSemantics(colorKey: "green", symbol: "checkmark.circle.fill", explanation: "已启用，正常可用")
        case .disabled:
            StatusSemantics(colorKey: "amber", symbol: "pause.circle.fill", explanation: "已禁用，存放于统一禁用区，可随时恢复")
        case .changed:
            StatusSemantics(colorKey: "amber", symbol: "arrow.triangle.2.circlepath", explanation: "内容有变更，可查看快照历史")
        case .conflict:
            StatusSemantics(colorKey: "red", symbol: "exclamationmark.triangle.fill", explanation: "路径冲突，需要处理后才能继续操作")
        case .permissionDenied:
            StatusSemantics(colorKey: "red", symbol: "lock.fill", explanation: "目录权限受限，需在系统设置中授权")
        case .unrecognized:
            StatusSemantics(colorKey: "amber", symbol: "questionmark.folder.fill", explanation: "目录结构与已知格式不匹配，已记录诊断")
        }
    }
}
