import Foundation
import Testing
import AppCore
@testable import AgentKeeperUI

/// 扫描状态条文案（spec：手动扫描必须有可见反馈——完成文案带时间戳与 skill 数，
/// 每次扫描后用户都能看到变化，而不是点击「无反应」）。i18n：中英双语文案断言。
@MainActor
@Suite struct ScanStatusTextTests {
    private let zh = L10n(lang: .zhHans)
    private let en = L10n(lang: .english)

    @Test func idle() {
        #expect(ScanStatusText.build(scan: ScanPhaseState(), skillsCount: 0, l10n: zh).contains("尚未扫描"))
        #expect(ScanStatusText.build(scan: ScanPhaseState(), skillsCount: 0, l10n: en).contains("Not scanned"))
    }

    @Test func running() {
        var scan = ScanPhaseState()
        scan.phase = .running
        #expect(ScanStatusText.build(scan: scan, skillsCount: 0, l10n: zh).contains("正在扫描"))
        #expect(ScanStatusText.build(scan: scan, skillsCount: 0, l10n: en).contains("Scanning"))
    }

    @Test func completeIncludesCountsAndTimestamp() {
        var scan = ScanPhaseState()
        scan.phase = .complete
        scan.agentCount = 1
        scan.diagnosticCount = 0
        scan.lastCompletedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let text = ScanStatusText.build(scan: scan, skillsCount: 3, l10n: zh)
        #expect(text.contains("1 agents"))
        #expect(text.contains("3 skills"))
        #expect(text.contains(ScanStatusText.clockText(scan.lastCompletedAt!)))
    }

    @Test func failedShowsMessage() {
        var scan = ScanPhaseState()
        scan.phase = .failed
        scan.failureMessage = "权限受限：/Users/x"
        let text = ScanStatusText.build(scan: scan, skillsCount: 0, l10n: zh)
        #expect(text.contains("权限受限"))
        let enText = ScanStatusText.build(scan: scan, skillsCount: 0, l10n: en)
        #expect(enText.contains("/Users/x"))
    }

    /// 窄侧栏（min 200pt）下全文案会换行——紧凑版必须更短且保留关键信息。
    @Test func compactFitsNarrowSidebar() {
        var scan = ScanPhaseState()
        scan.phase = .complete
        scan.agentCount = 1
        scan.lastCompletedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let full = ScanStatusText.build(scan: scan, skillsCount: 32, l10n: zh)
        let compact = ScanStatusText.compact(scan: scan, skillsCount: 32, l10n: zh)
        #expect(compact.count < full.count)
        #expect(compact.contains("32"))
        #expect(compact.contains(":"))  // 保留时间
        #expect(!compact.contains("\n"))
    }
}
