import Foundation
import Testing
import DomainKit
@testable import AppCore

@Suite struct StatusSemanticsTests {
    @Test func normalStatusesAreGreen() {
        #expect(StatusSemantics.resolve(.enabled).colorKey == "green")
    }

    @Test func cautionStatusesAreAmber() {
        #expect(StatusSemantics.resolve(.disabled).colorKey == "amber")
        #expect(StatusSemantics.resolve(.unrecognized).colorKey == "amber")
    }

    @Test func actionableStatusesAreRed() {
        #expect(StatusSemantics.resolve(.conflict).colorKey == "red")
        #expect(StatusSemantics.resolve(.permissionDenied).colorKey == "red")
    }

    @Test func everyTokenHasIconAndHoverExplanation() {
        for token in StatusToken.allCases {
            let semantics = StatusSemantics.resolve(token)
            #expect(!semantics.symbol.isEmpty)
            // 悬停释义非空（spec：状态含义 SHALL 能通过悬停查明）
            #expect(!semantics.explanation.isEmpty)
        }
    }

    @Test func symbolsAreDistinctPerFamily() {
        // 语义图标不互相打架：正常 (checkmark) ≠ 注意 (exclamation) ≠ 危险 (x/or lock)
        #expect(StatusSemantics.resolve(.enabled).symbol != StatusSemantics.resolve(.conflict).symbol)
        #expect(StatusSemantics.resolve(.disabled).symbol != StatusSemantics.resolve(.enabled).symbol)
    }
}
