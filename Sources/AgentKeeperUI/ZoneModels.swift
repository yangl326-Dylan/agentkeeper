import Foundation
import AppCore
import DomainKit
import InfraKit

// LifecycleZone 已迁至 AppCore/NavigationModel.swift（侧栏节点模型需要它做纯函数映射）。

/// 区行模型：停用区 / 回收站列表条目（manifest 合成——目录本体在 keeper 管辖下）。
@MainActor
public struct ZoneRowModel: Identifiable, Equatable, Sendable {
    /// manifest 定位（唯一——恢复动作按 (agentID, name) 定位）。
    public let id: String
    public let name: String
    public let agentID: AgentID
    /// 恢复目标路径。
    public let originalPath: String
    public let disabledAt: Date?

    public init(id: String, name: String, agentID: AgentID, originalPath: String, disabledAt: Date?) {
        self.id = id
        self.name = name
        self.agentID = agentID
        self.originalPath = originalPath
        self.disabledAt = disabledAt
    }
}

/// 生命周期区纯映射：manifest entries → 行模型（按 (agent, 名称) 稳定排序）。
@MainActor
public enum ZoneListModel {
    public static func build(entries: [SkillLifecycle.ZoneEntry]) -> [ZoneRowModel] {
        entries
            .sorted { lhs, rhs in
                if lhs.record.agentID != rhs.record.agentID {
                    return lhs.record.agentID < rhs.record.agentID
                }
                return lhs.record.name < rhs.record.name
            }
            .map { entry in
                ZoneRowModel(
                    id: entry.manifestPath,
                    name: entry.record.name,
                    agentID: entry.record.agentID,
                    originalPath: entry.record.originalPath,
                    disabledAt: entry.record.disabledAt
                )
            }
    }

    /// 侧栏徽章计数。
    public static func count(rows: [ZoneRowModel]) -> Int { rows.count }

    /// 侧栏节点文案（带计数）。
    public static func zoneTitle(zone: LifecycleZone, rows: [ZoneRowModel], l10n: L10n) -> String {
        "\(zone.title(l10n)) · \(rows.count)"
    }
}
