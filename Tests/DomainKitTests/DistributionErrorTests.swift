import Foundation
import Testing
import DomainKit

@Suite struct DistributionErrorTests {
    @Test func allCarriersHashableAndSendable() {
        let errors: [DistributionError] = [
            .conflict(DistributionConflict(targetPath: "/t", existingSha256: nil, incomingSha256: "x")),
            .invalidSource(reason: "缺少 SKILL.md"),
            .cloneFailed(detail: "git stderr: not found"),
            .cloneTimeout,
            .ioFailure(path: "/t", underlyingDescription: "EACCES"),
            .alreadyDistributed(targetPath: "/t"),
        ]
        #expect(Set(errors).count == errors.count)
        #expect(errors[0] == errors[0])
    }

    @Test func conflictCarrierPreserved() {
        let original = DistributionConflict(targetPath: "/t", existingSha256: "a", incomingSha256: "b")
        guard case let .conflict(carried) = DistributionError.conflict(original) else {
            Issue.record("expected conflict carrier")
            return
        }
        #expect(carried == original)
    }

    @Test func invalidSourceReasonReadable() {
        guard case let .invalidSource(reason: reason) = DistributionError.invalidSource(reason: "frontmatter 不合法") else {
            Issue.record("expected invalidSource")
            return
        }
        #expect(reason == "frontmatter 不合法")
    }
}
