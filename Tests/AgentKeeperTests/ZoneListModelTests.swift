import Foundation
import Testing
import DomainKit
import InfraKit
import AppCore
@testable import AgentKeeperUI

/// 停用区/回收站的行模型（ZoneListModel）——侧栏计数 + 区行渲染共用的纯映射。
@MainActor
@Suite struct ZoneListModelTests {
    private func entry(agent: String, name: String, original: String) -> SkillLifecycle.ZoneEntry {
        SkillLifecycle.ZoneEntry(
            record: DisabledSkillRecord(
                originalPath: original,
                agentID: agent,
                name: name,
                sha256: "sha-\(name)",
                disabledAt: Date(timeIntervalSince1970: 1_700_000_000)
            ),
            directoryPath: "/zone/\(agent)/\(name)",
            manifestPath: "/zone/\(agent)/\(name).manifest.json"
        )
    }

    /// 行映射：名称/agent/原路径/时间齐备；按 (agent, 名称) 排序稳定。
    @Test func rowsMapEntriesSortedByName() {
        let rows = ZoneListModel.build(entries: [
            entry(agent: "opencode", name: "zeta", original: "/h/.opencode/skills/zeta"),
            entry(agent: "claude-code", name: "alpha", original: "/h/.claude/skills/alpha"),
        ])
        #expect(rows.count == 2)
        #expect(rows[0].name == "alpha")
        #expect(rows[0].agentID == "claude-code")
        #expect(rows[0].originalPath == "/h/.claude/skills/alpha")
        #expect(rows[0].disabledAt?.timeIntervalSince1970 == 1_700_000_000)
        #expect(rows[1].name == "zeta")
    }

    /// 分区计数（侧栏徽章）：空区为 0。
    @Test func emptyZoneCountsZero() {
        #expect(ZoneListModel.build(entries: []).isEmpty)
        #expect(ZoneListModel.count(rows: []) == 0)
        let rows = ZoneListModel.build(entries: [entry(agent: "claude-code", name: "one", original: "/x")])
        #expect(ZoneListModel.count(rows: rows) == 1)
    }

    /// 侧栏节点行文案（带计数；i18n 双语断言）。
    @Test func sidebarNodeTitlesCarryCounts() {
        let rows = ZoneListModel.build(entries: [
            entry(agent: "claude-code", name: "one", original: "/x"),
            entry(agent: "opencode", name: "two", original: "/y"),
        ])
        let zh = L10n(lang: .zhHans)
        let en = L10n(lang: .english)
        #expect(ZoneListModel.zoneTitle(zone: .disabled, rows: rows, l10n: zh) == "停用区 · 2")
        #expect(ZoneListModel.zoneTitle(zone: .trash, rows: [], l10n: zh) == "回收站 · 0")
        #expect(ZoneListModel.zoneTitle(zone: .disabled, rows: rows, l10n: en) == "Disabled · 2")
        #expect(ZoneListModel.zoneTitle(zone: .trash, rows: [], l10n: en) == "Trash · 0")
    }
}
