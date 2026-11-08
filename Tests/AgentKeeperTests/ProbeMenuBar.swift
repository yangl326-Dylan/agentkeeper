import Foundation
import Testing
import SwiftUI
import AppKit
import DomainKit
import AppCore
@testable import AgentKeeperUI

/// 菜单栏面板组件：NSHostingView 位图渲染探针（出真实像素才算渲染成功）。
@MainActor
@Suite struct ProbeMenuBar {
    @Test func panelComponentsRenderToPixels() throws {
        func probe(_ view: some View, name: String) throws {
            let hosted = NSHostingView(rootView: view.frame(width: 260))
            hosted.frame = NSRect(x: 0, y: 0, width: 260, height: 120)
            hosted.layoutSubtreeIfNeeded()
            let rep = hosted.bitmapImageRepForCachingDisplay(in: hosted.bounds)!
            hosted.cacheDisplay(in: hosted.bounds, to: rep)
            let png = rep.representation(using: .png, properties: [:])!
            try FileManager.default.createDirectory(atPath: "/tmp/ak-ui", withIntermediateDirectories: true)
            try png.write(to: URL(fileURLWithPath: "/tmp/ak-ui/menubar-\(name).png"))
            #expect(png.count > 1000) // 非全透明才有内容
        }

        try probe(
            MenuBarHeaderRow(agentCount: 3, totalSkills: 86),
            name: "header"
        )
        try probe(
            MenuBarAgentRow(
                name: "Claude Code",
                icon: MenuBarIcons.icon(for: "claude-code"),
                skillCount: 53,
                targetDirectory: URL(fileURLWithPath: "/tmp"),
                onSelect: {}
            ),
            name: "agent-row"
        )
        try probe(
            MenuPanelActions(isScanning: false, onOpenMain: {}, onScan: {}, onQuit: {}),
            name: "actions"
        )
    }
}
