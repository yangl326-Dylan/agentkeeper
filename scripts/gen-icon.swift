#!/bin/swift
//
// gen-icon.swift — 生成 AgentKeeper.app 图标（AppIcon.icns）
// 主窗口引导页同款「带箭头的箱子」SF Symbol（shippingbox.and.arrow.backward.fill）
// + Claude 色系（陶土橙渐变底 + 象牙符号）。
//
// 产出: build/AppIcon.iconset/ + build/AppIcon.icns
//

import AppKit

let S: CGFloat = 1024

func nsColor(_ hex: UInt32) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: 1
    )
}

// Claude 色系：陶土橙渐变底 + 象牙符号
let gradientTop = nsColor(0xE08A67)   // 亮陶土
let gradientBottom = nsColor(0xC05F3D) // 深陶土
let glyphColor = nsColor(0xFAF9F5)     // 象牙

// 1) 渲染母版（全出血方形——macOS 自动施加圆角遮罩）
func renderMaster(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    // 背景：对角渐变
    let bg = NSGradient(starting: gradientTop, ending: gradientBottom)!
    bg.draw(
        in: NSRect(x: 0, y: 0, width: size, height: size),
        angle: -90
    )

    // 符号：带箭头的箱子（引导页/菜单栏同款）
    let config = NSImage.SymbolConfiguration(pointSize: size * 0.30, weight: .medium)
    if let base = NSImage(systemSymbolName: "shippingbox.and.arrow.backward.fill", accessibilityDescription: nil),
       let symbol = base.withSymbolConfiguration(config) {
        let symbolSize = size * 0.56
        let rect = NSRect(
            x: (size - symbolSize) / 2,
            y: (size - symbolSize) / 2,
            width: symbolSize,
            height: symbolSize
        )
        // 先画模板符号（黑），再用 sourceIn 重染为象牙色
        let tinted = NSImage(size: rect.size)
        tinted.lockFocus()
        symbol.draw(in: NSRect(origin: .zero, size: rect.size))
        NSGraphicsContext.current?.imageInterpolation = .high
        glyphColor.setFill()
        NSRect(origin: .zero, size: rect.size).fill(using: .sourceIn)
        tinted.unlockFocus()
        tinted.draw(in: rect)
    }

    image.unlockFocus()
    return image
}

// 2) 写 iconset 全尺寸
func writePNG(_ image: NSImage, size: CGFloat, to url: URL) {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size),
        pixelsHigh: Int(size),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()
    let png = rep.representation(using: .png, properties: [:])!
    try! png.write(to: url)
}

let work = URL(fileURLWithPath: "build/AppIcon.iconset", isDirectory: true)
try! FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

let master = renderMaster(size: S)
let sizes: [(CGFloat, String)] = [
    (16, "icon_16x16.png"), (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"), (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"), (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"), (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"), (1024, "icon_512x512@2x.png"),
]
for (size, name) in sizes {
    writePNG(master, size: size, to: work.appendingPathComponent(name))
}
print("iconset written: \(work.path)")
