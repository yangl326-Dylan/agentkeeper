import Foundation
import Testing
import AppCore
@testable import AgentKeeperUI

/// 扫描状态条文案（spec：手动扫描必须有可见反馈——完成文案带时间戳与 skill 数，
/// 每次扫描后用户都能看到变化，而不是点击「无反应」）。
@MainActor
@Suite struct ScanStatusTextTests {
    @Test func idle() {
        let text = ScanStatusText.build(scan: ScanPhaseState(), skillsCount: 0)
        #expect(text.contains("尚未扫描"))
    }

    @Test func running() {
        var scan = ScanPhaseState()
        scan.phase = .running
        let text = ScanStatusText.build(scan: scan, skillsCount: 0)
        #expect(text.contains("正在扫描"))
    }

    @Test func completeIncludesCountsAndTimestamp() {
        var scan = ScanPhaseState()
        scan.phase = .complete
        scan.agentCount = 1
        scan.diagnosticCount = 0
        scan.lastCompletedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let text = ScanStatusText.build(scan: scan, skillsCount: 3)
        #expect(text.contains("1 agents"))
        #expect(text.contains("3 skills"))
        #expect(text.contains(ScanStatusText.clockText(scan.lastCompletedAt!)))
    }

    @Test func failedShowsMessage() {
        var scan = ScanPhaseState()
        scan.phase = .failed
        scan.failureMessage = "权限受限：/Users/x"
        let text = ScanStatusText.build(scan: scan, skillsCount: 0)
        #expect(text.contains("权限受限"))
    }
}
