import Foundation
import Testing
import SwiftUI
import AppKit
@testable import AgentKeeperUI

/// Claude 色系：陶土橙 accent + **macOS 系统语义色**（标杆软件同款——
/// windowBackgroundColor / controlBackgroundColor / textColor，日夜间自动取标准值）。
@MainActor
@Suite struct ClaudePaletteTests {
    /// 在指定外观下解析动态色（现代 API，绕开已弃用的 .current 读写）。
    private func resolveComponents(_ color: NSColor, in appearance: NSAppearance)
        -> (red: CGFloat, green: CGFloat, blue: CGFloat)
    {
        var result: (red: CGFloat, green: CGFloat, blue: CGFloat)!
        appearance.performAsCurrentDrawingAppearance {
            let resolved = color.usingColorSpace(.sRGB)!
            result = (resolved.redComponent, resolved.greenComponent, resolved.blueComponent)
        }
        return result
    }

    private func luma(_ c: (red: CGFloat, green: CGFloat, blue: CGFloat)) -> CGFloat {
        0.2126 * c.red + 0.7152 * c.green + 0.0722 * c.blue
    }

    private static let aqua = NSAppearance(named: .aqua)!
    private static let dark = NSAppearance(named: .darkAqua)!

    @Test func accentIsClaudeTerracotta() {
        let ns = NSColor(ClaudePalette.accent).usingColorSpace(.sRGB)!
        #expect(abs(ns.redComponent - 217.0 / 255.0) < 0.001)
        #expect(abs(ns.greenComponent - 119.0 / 255.0) < 0.001)
        #expect(abs(ns.blueComponent - 87.0 / 255.0) < 0.001)
    }

    /// 背景 = 系统 windowBackgroundColor（日/夜都与系统 resolved 值一致）。
    @Test func backgroundMatchesSystemWindowBackground() {
        let system = NSColor.windowBackgroundColor

        let light = resolveComponents(NSColor(ClaudePalette.background), in: Self.aqua)
        let systemLight = resolveComponents(system, in: Self.aqua)
        #expect(abs(light.red - systemLight.red) < 0.002)
        #expect(abs(light.green - systemLight.green) < 0.002)
        #expect(abs(light.blue - systemLight.blue) < 0.002)

        let darkResolved = resolveComponents(NSColor(ClaudePalette.background), in: Self.dark)
        let systemDark = resolveComponents(system, in: Self.dark)
        #expect(abs(darkResolved.red - systemDark.red) < 0.002)
        #expect(abs(darkResolved.green - systemDark.green) < 0.002)
        #expect(abs(darkResolved.blue - systemDark.blue) < 0.002)
    }

    /// 主文字 = 系统 textColor：日间近纯黑（不再发浅）、夜间白档；卡片日白夜深对比清晰。
    @Test func textPrimaryMatchesSystemTextAndContrastOnCard() {
        let textLight = resolveComponents(NSColor(ClaudePalette.textPrimary), in: Self.aqua)
        #expect(luma(textLight) < 0.35)
        let cardLight = resolveComponents(NSColor(ClaudePalette.card), in: Self.aqua)
        #expect(luma(cardLight) > 0.85)

        let textDark = resolveComponents(NSColor(ClaudePalette.textPrimary), in: Self.dark)
        #expect(luma(textDark) > 0.7)
        let cardDark = resolveComponents(NSColor(ClaudePalette.card), in: Self.dark)
        #expect(luma(cardDark) < 0.35)
    }

    @Test func hexInitParses() {
        let ns = NSColor(Color(hex: 0x0000FF)).usingColorSpace(.sRGB)!
        #expect(ns.blueComponent > 0.999)
    }
}
