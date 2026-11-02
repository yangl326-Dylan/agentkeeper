import AppKit
import Testing
@testable import AgentKeeperUI

/// 状态栏字形（「收藏匣」母题的 template 投影）。
@MainActor
@Suite struct MenuBarIconTests {
    /// template 属性是菜单栏明暗自适应的前提；18pt 是状态栏基线尺寸。
    @Test func glyphIsTemplateAtStatusBarBaseline() {
        let image = MenuBarIcon.templateImage()
        #expect(image.isTemplate == true)
        #expect(image.size.width == 18)
        #expect(image.size.height == 18)
        let pixels = image.representations.first
        #expect(pixels?.pixelsWide == 36)
        #expect(pixels?.pixelsHigh == 36)
    }

    /// 母题验证：2×2 三实一空——室内格有墨、外圈四角落空（状态栏 respiros 留白）。
    @Test func glyphHasInkInsideAndClearCorners() async throws {
        let image = MenuBarIcon.templateImage()
        let tiff = try #require(image.tiffRepresentation)
        let rep = try #require(NSBitmapImageRep(data: tiff))
        #expect(rep.pixelsWide == 36)

        func alphaAt(_ x: Int, _ y: Int) -> CGFloat {
            // 输出物以 2x 光栅；行列均以像素计
            (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0)
        }

        // 像素坐标：col = cg_x（不翻转）；row = 36-1-cg_y（上下翻转）
        // 左下格中心（有墨）
        #expect(alphaAt(13, 23) > 0.2, "左下格应有墨")
        // 左上格中心也有墨（三实）
        #expect(alphaAt(13, 12) > 0.2, "左上格应有墨")
        // 右上格中心（留空——「还有下一格」）
        #expect(alphaAt(23, 12) < 0.05, "右上格应留空")
        // 四角落空（外圈留白半径）
        #expect(alphaAt(1, 1) < 0.05)
        #expect(alphaAt(34, 34) < 0.05)
        #expect(alphaAt(1, 34) < 0.05)
        #expect(alphaAt(34, 1) < 0.05)
    }
}
