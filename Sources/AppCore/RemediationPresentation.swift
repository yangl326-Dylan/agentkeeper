import Foundation
import DomainKit

/// 诊断的展示模型（错误呈现不阻断：内联卡片 + 跳转引导）。
public struct RemediationCard: Hashable, Sendable {
    public var title: String
    public var detail: String
    /// nil = 仅展示，无跳转。
    public var actionLabel: String?
    public var isActionable: Bool { actionLabel != nil }
}

/// ScanDiagnostic → 展示模型的唯一映射。
public enum RemediationPresentation {
    public static func present(_ diagnostic: ScanDiagnostic) -> RemediationCard {
        var card = RemediationCard(
            title: Self.title(for: diagnostic),
            detail: diagnostic.message + " · " + diagnostic.path,
            actionLabel: nil
        )
        switch diagnostic.remediation {
        case .grantAccess:
            card.actionLabel = "查看授权引导"
        case .retry:
            card.actionLabel = "重试扫描"
        case .none:
            card.actionLabel = nil
        }
        return card
    }

    private static func title(for diagnostic: ScanDiagnostic) -> String {
        switch diagnostic.kind {
        case .permissionDenied: "权限受限"
        case .unrecognizedStructure: "无法识别的目录结构"
        case .ioError: "读取失败"
        }
    }
}
