import AppKit

/// 状态栏字形（MenuBarExtra label）——「收藏匣」母题的极简 template 投影。
///
/// 母题：圆角托盘描边 + 2×2 三实一空的格架。留空的一格是叙事——
/// 「还有下一格等着被收纳」；与 App 图标（docs/design/keeper-icon-philosophy.md）
/// 共用同一构图秩序。单色 template：菜单栏明暗模式下系统自动反色。
///
/// 绘制约束：36px（18pt @2x）定尺寸光栅（不走 lockFocus——像素规模随屏幕
/// backing scale 漂移的不可控）；几何全部按像素比例计算，任何目标尺寸等比成立。
@MainActor
public enum MenuBarIcon {
    /// 18pt 基线 template 字形（固定 36px @2x 位图载体）。
    public static func templateImage() -> NSImage {
        let pixelCount = 36
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelCount,
            pixelsHigh: pixelCount,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        // template 只取 alpha：纯黑墨 + 系统重染
        NSColor.black.setFill()
        NSColor.black.setStroke()
        drawGlyph(side: CGFloat(pixelCount))
        NSGraphicsContext.restoreGraphicsState()
        // size 在绘制后设置（先设会改变 bitmapRep context 的 CTM——坐标系被 2x 放大）
        rep.size = NSSize(width: 18, height: 18)

        let image = NSImage(size: NSSize(width: 18, height: 18))
        image.addRepresentation(rep)
        image.isTemplate = true
        image.accessibilityDescription = "AgentKeeper"
        return image
    }

    /// 字形本体（像素比例坐标：side = 画布像素边长）。
    /// 托盘：圆角方描边（占 74%）；格架：2×2 三实一空，右上留空。
    static func drawGlyph(side: CGFloat) {
        let trayInset = side * (3.5 / 36.0)
        let trayRect = NSRect(x: trayInset, y: trayInset, width: side - trayInset * 2, height: side - trayInset * 2)
        let trayPath = NSBezierPath(roundedRect: trayRect, xRadius: side * (9.0 / 36.0), yRadius: side * (9.0 / 36.0))
        trayPath.lineWidth = side * (2.8 / 36.0)
        trayPath.stroke()

        // 格架：以内缘等距内缩出 2×2；右上格留空
        let trayLineWidth = side * (2.8 / 36.0)
        let innerInset = trayInset + trayLineWidth + side * (2.2 / 36.0)
        let innerSide = side - innerInset * 2
        let cell = (innerSide - side * (2.0 / 36.0)) / 2
        let gap = cell + side * (2.0 / 36.0)
        let cellRadius = cell * 0.30
        let positions: [NSPoint] = [
            // (x, y) 左下原点；跳过右上格（index 3）
            NSPoint(x: innerInset, y: innerInset),
            NSPoint(x: innerInset + gap, y: innerInset),
            NSPoint(x: innerInset, y: innerInset + gap),
        ]
        for origin in positions {
            let cellRect = NSRect(x: origin.x, y: origin.y, width: cell, height: cell)
            NSBezierPath(roundedRect: cellRect, xRadius: cellRadius, yRadius: cellRadius).fill()
        }
    }
}
