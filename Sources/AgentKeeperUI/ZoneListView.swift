import SwiftUI
import AppCore
import DomainKit

/// 停用区 / 回收站列表（侧栏「生命周期」分区选中后的列表位）。
/// 行内动作：停用区 → 启用；回收站 → 恢复 / 彻底删除；回收站 toolbar → 清空。
/// 不可逆动作（彻底删除 / 清空）一律二次确认；其余动作零确认（全部可逆）。
@MainActor
public struct ZoneListView: View {
    let zone: LifecycleZone
    @Environment(AppEnvironment.self) private var env
    @State private var confirmPurge: ZoneRowModel?
    @State private var confirmPurgeAll = false

    public init(zone: LifecycleZone) {
        self.zone = zone
    }

    public var body: some View {
        let l = env.l10n
        let rows = zone == .disabled ? env.disabledZoneRows() : env.trashedZoneRows()
        List {
            if rows.isEmpty {
                ContentUnavailableView(
                    zone == .disabled ? l.zoneDisabledEmpty : l.zoneTrashEmpty,
                    systemImage: zone == .disabled ? "pause.circle" : "trash",
                    description: Text(zone == .disabled
                        ? l.zoneDisabledEmptyDetail
                        : l.zoneTrashEmptyDetail)
                )
            } else {
                ForEach(rows) { row in
                    ZoneRowView(
                        zone: zone,
                        row: row,
                        l10n: l,
                        onRestore: {
                            Task { await env.enableFromZone(zone: zone, row: row) }
                        },
                        onPurge: {
                            confirmPurge = row
                        }
                    )
                    .padding(.horizontal, 8)
                }
            }
        }
        .toolbar {
            if zone == .trash, !rows.isEmpty {
                ToolbarItem {
                    Button {
                        confirmPurgeAll = true
                    } label: {
                        Label(l.zoneEmptyTrash, systemImage: "trash.slash")
                    }
                    .help(l.zoneEmptyTrashHelp)
                }
            }
        }
        // 详情层（不可逆确认）：彻底删除单个
        .alert(
            l.zonePurgeTitle(confirmPurge?.name ?? ""),
            isPresented: Binding(
                get: { confirmPurge != nil },
                set: { if !$0 { confirmPurge = nil } }
            )
        ) {
            Button(l.zonePurgeButton, role: .destructive) {
                if let row = confirmPurge {
                    Task { await env.purgeTrashEntry(row) }
                }
                confirmPurge = nil
            }
            Button(l.commonCancel, role: .cancel) { confirmPurge = nil }
        } message: {
            Text(l.zonePurgeMessage(confirmPurge?.originalPath ?? ""))
        }
        // 清空回收站（不可逆 + 数量明细）
        .alert(
            l.zoneEmptyTrashTitle(env.trashedZoneRows().count),
            isPresented: $confirmPurgeAll
        ) {
            Button(l.zoneEmptyButton, role: .destructive) {
                Task { await env.purgeAllTrash() }
            }
            Button(l.commonCancel, role: .cancel) { }
        } message: {
            Text(l.zoneEmptyTrashMessage)
        }
        .overlay(alignment: .bottom) {
            operationBanner
        }
    }

    /// 操作结果横幅（状态机广播：冲突明细 / 进行中提示）。
    private var operationBanner: some View {
        let state = env.store.state.operation
        return Group {
            if state.inFlight != nil {
                Label(env.l10n.zonePerforming, systemImage: "hourglass")
            } else if let failure = state.failureMessage {
                Label(failure, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color(nsColor: .systemOrange))
                    .lineLimit(2)
            }
        }
        .font(.callout)
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(ClaudePalette.card)
                .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
        )
        .padding(.bottom, 12)
        .opacity(state.inFlight != nil || state.failureMessage != nil ? 1 : 0)
        .animation(.easeInOut(duration: 0.15), value: state.failureMessage == nil)
    }
}

/// 区行内容（独立 struct：UISnapshot 离屏渲染可引用——List 整体不出像素）。
@MainActor
public struct ZoneRowView: View {
    let zone: LifecycleZone
    let row: ZoneRowModel
    var l10n: L10n = L10n(lang: .zhHans)
    /// 行动作回调（ZoneListView 注入——含确认弹窗逻辑）。
    var onRestore: () -> Void = {}
    var onPurge: () -> Void = {}

    public var body: some View {
        HStack(spacing: 14) {
            Image(systemName: zone == .disabled ? "pause.circle.fill" : "trash")
                .foregroundStyle(zone == .disabled ? Color(nsColor: .systemOrange) : Color(nsColor: .secondaryLabelColor))
                .font(.title3)
            VStack(alignment: .leading, spacing: 4) {
                Text(row.name)
                    .font(.headline)
                // 若停用/删除后原路径又被创建，恢复将以冲突中止（明细走操作状态机）
                Text(row.originalPath)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                if let at = row.disabledAt {
                    Text("\(zone == .disabled ? l10n.zoneDisabledAt : l10n.zoneDeletedAt)\(at.formatted(date: .abbreviated, time: .shortened)) · \(row.agentID)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            // 可逆动作零确认；不可逆动作（彻底删除）先弹窗
            switch zone {
            case .disabled:
                Button(action: onRestore) {
                    Label(l10n.zoneEnableButton, systemImage: "checkmark.circle")
                }
                .help(l10n.zoneRestoreHelp)
            case .trash:
                Button(action: onRestore) {
                    Label(l10n.zoneRestoreButton, systemImage: "arrow.uturn.backward.circle")
                }
                .help(l10n.zoneRestoreHelp)
                Button(role: .destructive, action: onPurge) {
                    Label(l10n.zonePurgeButton, systemImage: "trash.fill")
                }
                .help(l10n.zonePurgeRowHelp)
            }
        }
    }
}
