import Foundation
import Testing
import SwiftUI
import AppKit
import DomainKit
import AppCore
@testable import AgentKeeperUI

@MainActor
@Suite struct ProbeRender {
    /// J：NSHostingView.cacheDisplay 位图管线（验证 List/ScrollView 是否可出真实像素）
    @Test func hostingViewCache() throws {
        let home = makeFakeHomeCore(files: ["d"])
        defer { try? FileManager.default.removeItem(at: home) }
        let env = AppEnvironment(homeDirectory: home)
        env.catalogStore.sync(with: UIWiring.demoSkills(home: home))
        let content = VStack(spacing: 12) {
            List {
                ForEach(env.catalogStore.current) { skill in
                    HStack {
                        Image(systemName: "-circle" == "x" ? "circle" : "circle")
                        Text(skill.name)
                    }
                }
            }
            Button("测试按钮") { }
        }
        .frame(width: 300, height: 400)
        let hosting = NSHostingView(rootView: content.environment(env))
        hosting.frame = NSRect(x: 0, y: 0, width: 300, height: 400)
        hosting.layoutSubtreeIfNeeded()
        let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds)!
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        let png: Data = rep.representation(using: .png, properties: [:])!
        // CI 干净环境：目录不存在会写失败（本机曾因残留目录而掩盖此问题）
        try FileManager.default.createDirectory(
            atPath: "/tmp/ak-ui", withIntermediateDirectories: true
        )
        try png.write(to: URL(fileURLWithPath: "/tmp/ak-ui/probe-J.png"))
    }
}
