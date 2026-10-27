import Foundation
import Testing
import DomainKit
@testable import AppCore

@Suite struct RemediationPresentationTests {
    @Test func permissionDeniedProducesGuidanceCard() {
        let diagnostic = ScanDiagnostic(
            path: "/Users/x/secret",
            kind: .permissionDenied,
            agentID: "claude-code",
            message: "目录无法读取（权限受限）",
            remediation: .grantAccess
        )
        let card = RemediationPresentation.present(diagnostic)
        #expect(card.title.contains("权限"))
        #expect(card.detail.contains("/Users/x/secret"))
        #expect(card.actionLabel == "查看授权引导")
        #expect(card.isActionable)
    }

    @Test func unrecognizedStructureIsInformational() {
        let diagnostic = ScanDiagnostic(
            path: "/Users/x/.weirdagent",
            kind: .unrecognizedStructure,
            agentID: nil,
            message: "结构与已知格式不匹配",
            remediation: .none
        )
        let card = RemediationPresentation.present(diagnostic)
        #expect(card.actionLabel == nil)
        #expect(card.isActionable == false)
    }

    @Test func retryDiagnosticsOfferRetryAction() {
        let diagnostic = ScanDiagnostic(
            path: "/tmp/io",
            kind: .ioError,
            agentID: "codex",
            message: "IO 失败",
            remediation: .retry
        )
        let card = RemediationPresentation.present(diagnostic)
        #expect(card.actionLabel != nil)
        #expect(card.isActionable)
    }
}
