import Foundation
import Testing
import SwiftUI
import AppKit
@testable import AgentKeeperUI

/// Claude 色系（Anthropic 品牌色）：陶土橙 accent + 象牙底 + 暖炭黑文字/暗色底。
@MainActor
@Suite struct ClaudePaletteTests {
    @Test func accentIsClaudeTerracotta() {
        let ns = NSColor(ClaudePalette.accent).usingColorSpace(.sRGB)!
        #expect(abs(ns.redComponent - 217.0 / 255.0) < 0.001)
        #expect(abs(ns.greenComponent - 119.0 / 255.0) < 0.001)
        #expect(abs(ns.blueComponent - 87.0 / 255.0) < 0.001)
    }

    @Test func backgroundIsDynamicIvoryDark() {
        let ns = NSColor(ClaudePalette.background)
        let previous = NSAppearance.current
        defer { NSAppearance.current = previous }

        NSAppearance.current = NSAppearance(named: .aqua)
        let light = ns.usingColorSpace(.sRGB)!
        #expect(abs(light.redComponent - 0xF0 / 255.0) < 0.002)
        #expect(abs(light.greenComponent - 0xEE / 255.0) < 0.002)
        #expect(abs(light.blueComponent - 0xE6 / 255.0) < 0.002)

        NSAppearance.current = NSAppearance(named: .darkAqua)
        let dark = ns.usingColorSpace(.sRGB)!
        #expect(abs(dark.redComponent - 0x26 / 255.0) < 0.002)
    }

    @Test func cardColorsResolve() {
        _ = NSColor(ClaudePalette.card).usingColorSpace(.sRGB)
        _ = NSColor(ClaudePalette.textPrimary).usingColorSpace(.sRGB)
    }

    @Test func hexInitParses() {
        let ns = NSColor(Color(hex: 0x0000FF)).usingColorSpace(.sRGB)!
        #expect(ns.blueComponent > 0.999)
    }
}
