#!/bin/swift
//
// gen-icon.swift — 生成 AgentKeeper.app 图标（AppIcon.icns）
// 主窗口引导页同款「带箭头的箱子」SF Symbol（shippingbox.and.arrow.backward.fill）
// + Claude 色系（陶土橙渐变底 + 象牙符号）。
//
// 形状：macOS 标准 squircle（Finder 同款）——1024 画布上 824×824 圆角矩形
// （居中、四角 100px 留白透明），半径 ≈185；icns 不自动加圆角，必须自带 alpha。
// 每个输出尺寸独立重渲染（SF Symbol 按点阵光栅化，避免 1024 缩到 16 发糊）。
//
// 产出: build/AppIcon.iconset/ + build/AppIcon.icns
//

import AppKit

// Claude 色系
func nsColor(_ hex: UInt32) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: 1
    )
}

let gradientTop = nsColor(0xE08A67)    // 亮陶土
let gradientBottom = nsColor(0xC05F3D) // 深陶土
let glyphColor = nsColor(0xFAF9F5)     // 象牙
let borderColor = nsColor(0xA54E2F)    // 描边（深陶土）

// macOS 标准图标几何（Finder 比例）
let canvasMarginRatio: CGFloat = 100.0 / 1024.0 // 四边留白
let cornerRadiusRatio: CGFloat = 185.0 / 1024.0 // 圆角半径

// 1) 母版：圆角矩形（四角透明）+ 渐变 + 象牙符号 + 细描边
func renderMaster(size: CGFloat) -> NSImage {
    let margin = size * canvasMarginRatio
    let body = NSRect(
        x: margin, y: margin,
        width: size - margin * 2, height: size - margin * 2
    )
    let radius = size * cornerRadiusRatio
    let shape = NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)

    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    // 裁剪到 squircle（四角保持透明）
    shape.addClip()

    // 背景：对角渐变
    NSGradient(starting: gradientTop, ending: gradientBottom)?
        .draw(in: NSRect(x: 0, y: 0, width: size, height: size), angle: -90)

    // 符号：带箭头的箱子（引导页/菜单栏同款）
    let config = NSImage.SymbolConfiguration(pointSize: size * 0.30, weight: .medium)
    if let base = NSImage(systemSymbolName: "shippingbox.and.arrow.backward.fill", accessibilityDescription: nil),
       let symbol = base.withSymbolConfiguration(config) {
        let symbolSize = (size - margin * 2) * 0.62
        let rect = NSRect(
            x: (size - symbolSize) / 2,
            y: (size - symbolSize) / 2,
            width: symbolSize,
            height: symbolSize
        )
        // 模板符号（黑）→ sourceIn 重染象牙
        let tinted = NSImage(size: rect.size)
        tinted.lockFocus()
        symbol.draw(in: NSRect(origin: .zero, size: rect.size))
        glyphColor.setFill()
        NSRect(origin: .zero, size: rect.size).fill(using: .sourceIn)
        tinted.unlockFocus()
        tinted.draw(in: rect)
    }

    // 细描边（Finder 同款的边缘定义，8px @1024 等比缩放）
    shape.lineWidth = size * (8.0 / 1024.0)
    borderColor.setStroke()
    shape.stroke()

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

let sizes: [(CGFloat, String)] = [
    (16, "icon_16x16.png"), (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"), (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"), (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"), (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"), (1024, "icon_512x512@2x.png"),
]
for (size, name) in sizes {
    writePNG(renderMaster(size: size), size: size, to: work.appendingPathComponent(name))
}
print("iconset written: \(work.path)")
