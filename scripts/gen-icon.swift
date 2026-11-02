#!/bin/swift
//
// gen-icon.swift — 生成 AgentKeeper.app 图标（AppIcon.icns）
// 设计母题「收藏匣 / One More Slot」（docs/design/keeper-icon-philosophy.md）：
// 象牙纸 squircle 底 + 陶土开口匣（中央镂空透出纸底）+ 2×2 三实一空格架
// + 深炭滑入卡（收编动势）。Claude 品牌语言：大面积纸面留白 + 单一陶土主体。
//
// 形状：macOS 标准 squircle（Finder 同款）——1024 画布上 824×824 圆角矩形
// （居中、四角 100px 留白透明）；icns 不自动加圆角，必须自带 alpha。
// 每个输出尺寸独立重渲染（矢量几何按比例重算，避免位图缩放发糊）。
//
// 产出: build/AppIcon.iconset/ + build/AppIcon.icns
//

import AppKit

// MARK: - Claude 品牌色

func nsColor(_ hex: UInt32) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: 1
    )
}

// 纸面（Claude 象牙）
let paperTop = nsColor(0xFBFAF7)
let paperBottom = nsColor(0xF0EDE5)
let paperEdge = nsColor(0xD8D3C7)      // squircle 极细描边（纸缘投影感）
// 匣（陶土）
let trayTop = nsColor(0xDC7D5C)
let trayBottom = nsColor(0xB85A3B)
let trayEdge = nsColor(0xA54E2F)       // 匣外缘 hairline
// 收纳物
let cardFill = nsColor(0xFAF9F5)       // 已收纳的象牙卡
let cardEdge = nsColor(0xE2DCCE)       // 卡片轮廓
let incomingFill = nsColor(0x262624)   // 滑入中的炭卡（全图唯一深色重音）

// MARK: - 母版几何（1024 基准，全部按比例缩放）

let base: CGFloat = 1024
// Finder squircle：四边 100/1024 留白、圆角 185/1024
let squircleMarginRatio: CGFloat = 100.0 / 1024.0
let squircleRadiusRatio: CGFloat = 185.0 / 1024.0

/// 匣体在纸面 squircle 内的比例（以 1024 基准的绝对像素 → ratio 换算体）。
struct K {
    // 匣：居中 500×440，圆角 64
    static let trayW: CGFloat = 500
    static let trayH: CGFloat = 440
    static let trayBottom: CGFloat = 330
    static let trayRadius: CGFloat = 64
    // 镂空：匣内等距内缩 46，圆角 40
    static let holeInset: CGFloat = 46
    static let holeRadius: CGFloat = 40
    // 格架：镂空内再缩 26；cell gap 24；圆角 24
    static let cellPad: CGFloat = 26
    static let cellGap: CGFloat = 24
    static let cellRadius: CGFloat = 24
    // 滑入炭卡骑在匣顶缘 +22 右偏（半嵌空格——底部约 1/3 落在空格内）
    static let incomingLift: CGFloat = 96
    static let incomingShiftX: CGFloat = 22
    static let incomingAngle: CGFloat = -10
}

func scaled(_ v: CGFloat, size: CGFloat) -> CGFloat { v * size / base }

// MARK: - 母版渲染

func cellGeometry(hole: NSRect, size: CGFloat) -> (cellW: CGFloat, cellH: CGFloat, xs: [CGFloat], ys: [CGFloat]) {
    // hole 内等距 padding → 2×2
    let padX = scaled(K.cellPad, size: size)
    let padY = scaled(K.cellPad, size: size)
    let usableW = hole.width - padX * 2
    let usableH = hole.height - padY * 2
    let gap = scaled(K.cellGap, size: size)
    let cellW = (usableW - gap) / 2
    let cellH = (usableH - gap) / 2
    let x0 = hole.minX + padX
    let x1 = x0 + cellW + gap
    let y0 = hole.minY + padY
    let y1 = y0 + cellH + gap
    return (cellW, cellH, [x0, x1], [y0, y1])
}

/// 等比渲染一张图标（x 均 Cocoa 坐标，y 向上）。
func renderMaster(size: CGFloat) -> NSImage {
    let m = scaled(squircleMarginRatio * 1024, size: size)
    let squircle = NSRect(x: m, y: m, width: size - m * 2, height: size - m * 2)
    let radius = scaled(squircleRadiusRatio * 1024, size: size)
    let s = size / base // 几何比例因子

    // 尺寸换算快捷
    func g(_ v: CGFloat) -> CGFloat { v * s }

    // 匣绝对几何（基准 1024）
    let trayRect = NSRect(
        x: (base - K.trayW) / 2 * s,
        y: K.trayBottom * s,
        width: K.trayW * s,
        height: K.trayH * s
    )
    let holeInset = g(K.holeInset)
    let hole = trayRect.insetBy(dx: holeInset, dy: holeInset)

    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    // 裁剪到 squircle（四角保持透明）
    let squirclePath = NSBezierPath(roundedRect: squircle, xRadius: radius, yRadius: radius)
    squirclePath.addClip()

    // 1) 纸面：垂直微光渐变（上亮下微沉——纸的白并非死白）
    NSGradient(starting: paperTop, ending: paperBottom)?
        .draw(in: squircle, angle: 90)

    // 2) 开口匣：外框 + 镂空（even-odd）→ 透出纸底
    let trayPath = NSBezierPath(roundedRect: trayRect, xRadius: g(K.trayRadius), yRadius: g(K.trayRadius))
    let holePath = NSBezierPath(roundedRect: hole, xRadius: g(K.holeRadius), yRadius: g(K.holeRadius))
    trayPath.append(holePath)
    trayPath.windingRule = .evenOdd
    NSGradient(starting: trayTop, ending: trayBottom)?
        .draw(in: trayPath, angle: 90)
    // 匣外缘 hairline（Finder 式边缘定义）
    let trayOutline = NSBezierPath(roundedRect: trayRect, xRadius: g(K.trayRadius), yRadius: g(K.trayRadius))
    trayOutline.lineWidth = g(6)
    trayEdge.setStroke()
    trayOutline.stroke()

    // 3) 镂空内透出的纸底略沉一档（与象牙卡拉开对比）+ 上缘内阴影（匣口深度暗示）
    NSGraphicsContext.current?.saveGraphicsState()
    holePath.addClip()
    nsColor(0xEBE6DA).setFill()
    NSRect(
        x: hole.minX, y: hole.minY,
        width: hole.width, height: hole.height
    ).fill()
    nsColor(0x000000).withAlphaComponent(0.13).setFill()
    NSRect(
        x: hole.minX, y: hole.maxY - g(34),
        width: hole.width, height: g(34)
    ).fill()
    NSGraphicsContext.current?.restoreGraphicsState()

    // 4) 格架 2×2：三张象牙卡 + 右上留空（「还有下一格」）
    let geom = cellGeometry(hole: hole, size: size)
    let cardPath = { (x: CGFloat, y: CGFloat) in
        NSBezierPath(
            roundedRect: NSRect(x: x, y: y, width: geom.cellW, height: geom.cellH),
            xRadius: g(K.cellRadius), yRadius: g(K.cellRadius)
        )
    }
    // 已收纳三卡：左上、左下、右下（右上空）
    let cards: [(CGFloat, CGFloat)] = [
        (geom.xs[0], geom.ys[1]),
        (geom.xs[0], geom.ys[0]),
        (geom.xs[1], geom.ys[0]),
    ]
    for (x, y) in cards {
        let p = cardPath(x, y)
        cardFill.setFill()
        p.fill()
        cardEdge.setStroke()
        p.lineWidth = g(4)
        p.stroke()
    }

    // 5) 滑入炭卡：骑在匣顶缘、右偏、-10°，带轻投影（纸面悬浮）
    let slotCenterX = geom.xs[1] + geom.cellW / 2
    let slotCenterY = geom.ys[1] + geom.cellH / 2
    let incomingRect = NSRect(
        x: slotCenterX + g(K.incomingShiftX) - geom.cellW / 2,
        y: slotCenterY + g(K.incomingLift) - geom.cellH / 2,
        width: geom.cellW, height: geom.cellH
    )
    let incomingPath = NSBezierPath(
        roundedRect: incomingRect, xRadius: g(K.cellRadius), yRadius: g(K.cellRadius)
    )
    // 轻投影：纸面悬浮（收束——偏置距与柔度都低于首版）
    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = nsColor(0x191919).withAlphaComponent(0.14)
    shadow.shadowOffset = NSSize(width: 0, height: -g(8))
    shadow.shadowBlurRadius = g(16)
    shadow.set()
    // 以卡中心为轴 -10°倾角填充
    NSGraphicsContext.current?.cgContext.translateBy(x: incomingRect.midX, y: incomingRect.midY)
    NSGraphicsContext.current?.cgContext.rotate(by: K.incomingAngle * .pi / 180)
    NSGraphicsContext.current?.cgContext.translateBy(x: -incomingRect.midX, y: -incomingRect.midY)
    incomingFill.setFill()
    incomingPath.fill()
    NSGraphicsContext.current?.restoreGraphicsState()

    // 6) 速度虚线：贴着滑入反方向（右上）两道短线——短、细、淡（动势暗示，不做大尾迹）
    let dashColor = nsColor(0x262624)
    let dashSpecs: [(x: CGFloat, y: CGFloat, len: CGFloat, w: CGFloat, alpha: CGFloat)] = [
        (incomingRect.maxX + g(32), incomingRect.maxY - g(70), g(64), g(9), 0.24),
        (incomingRect.maxX + g(6), incomingRect.maxY - g(112), g(42), g(8), 0.13),
    ]
    for dash in dashSpecs {
        let line = NSBezierPath()
        line.move(to: NSPoint(x: dash.x, y: dash.y))
        line.line(to: NSPoint(x: dash.x + dash.len, y: dash.y + g(14)))
        line.lineWidth = dash.w
        line.lineCapStyle = .round
        dashColor.withAlphaComponent(dash.alpha).setStroke()
        line.stroke()
    }
    NSGraphicsContext.current?.restoreGraphicsState()

    // 7) 纸缘 hairline（squircle 轮廓定义）
    squirclePath.lineWidth = g(5)
    paperEdge.setStroke()
    squirclePath.stroke()

    image.unlockFocus()
    return image
}

// MARK: - 写 iconset 全尺寸

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

// 附加：母版大图探针（设计目检用；不进 icns）
writePNG(renderMaster(size: 512), size: 512, to: URL(fileURLWithPath: "build/icon-preview-512.png"))
print("iconset written: \(work.path)")
