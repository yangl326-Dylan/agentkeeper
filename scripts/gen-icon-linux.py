#!/usr/bin/env python3
"""gen-icon-linux.py — 生成 AgentKeeper Linux 桌面图标（与 macOS gen-icon.swift 同源）。

设计母题「收藏匣 / One More Slot」（docs/design/keeper-icon-philosophy.md）：
象牙纸 squircle 底 + 陶土开口匣 + 2×2 三实一空格架 + 深炭滑入卡。

几何/配色逐常量对齐 scripts/gen-icon.swift（1024 基准）：
- squircle：margin 100、圆角 185、纸渐变 #FBFAF7→#F0EDE5、缘 hairline #D8D3C7 w5
- 匣：500×440 @(262, svg254) 圆角 64、陶土渐变 #DC7D5C→#B85A3B、外缘 #A54E2F w6
- 镂空底：内缩 46 圆角 40、#EBE6DA + 顶部 34px 内阴影黑 13%
- 格架：pad 26 / gap 24 / 圆角 24 → 三卡（左上/左下/右下）#FAF9F5 边 #E2DCCE w4
- 滑入炭卡：右上格 +22 右偏 +96 上浮、-10°、#262624、投影 #191919 14% blur16 dy8
- 速度虚线 ×2：圆帽线（右上反方向）alpha .24/.13

产出：assets/icons/agentkeeper-{32,64,128,256,512}.png（独立重渲染，非位图缩放）。
用法：python3 scripts/gen-icon-linux.py
"""
from pathlib import Path

BASE = 1024.0

# 品牌/几何常量（与 gen-icon.swift 一一对应）
PAPER_TOP, PAPER_BOTTOM, PAPER_EDGE = "#FBFAF7", "#F0EDE5", "#D8D3C7"
TRAY_TOP, TRAY_BOTTOM, TRAY_EDGE = "#DC7D5C", "#B85A3B", "#A54E2F"
CARD_FILL, CARD_EDGE, INCOMING = "#FAF9F5", "#E2DCCE", "#262624"
HOLE_FILL = "#EBE6DA"

MARGIN, SQUIRCLE_R = 100.0, 185.0
TRAY_X, TRAY_Y, TRAY_W, TRAY_H, TRAY_R = 262.0, 254.0, 500.0, 440.0, 64.0
HOLE_INSET, HOLE_R = 46.0, 40.0
CELL_PAD, CELL_GAP, CELL_R = 26.0, 24.0, 24.0
INCOMING_SHIFT_X, INCOMING_LIFT, INCOMING_ANGLE = 22.0, 96.0, -10.0

# 镂空与格架派生（svg 坐标，y 向下）
HOLE_X, HOLE_Y = TRAY_X + HOLE_INSET, TRAY_Y + HOLE_INSET
HOLE_W, HOLE_H = TRAY_W - 2 * HOLE_INSET, TRAY_H - 2 * HOLE_INSET
CELL_W = (HOLE_W - 2 * CELL_PAD - CELL_GAP) / 2
CELL_H = (HOLE_H - 2 * CELL_PAD - CELL_GAP) / 2
CX0, CX1 = HOLE_X + CELL_PAD, HOLE_X + CELL_PAD + CELL_W + CELL_GAP
# Cocoa ys[0]=靠下 → svg 大 y；ys[1]=靠上 → svg 小 y
CY_TOP = HOLE_Y + CELL_PAD            # 326（svg 上排）
CY_BOTTOM = CY_TOP + CELL_H + CELL_GAP  # 486（svg 下排）

# 滑入炭卡（右上格中心 + 偏移，Cocoa -10° 逆时针 = SVG rotate(-10) 同向）
SLOT_CX, SLOT_CY = CX1 + CELL_W / 2, CY_TOP + CELL_H / 2
INC_X, INC_Y = SLOT_CX + INCOMING_SHIFT_X - CELL_W / 2, SLOT_CY - INCOMING_LIFT - CELL_H / 2
INC_CX, INC_CY = INC_X + CELL_W / 2, INC_Y + CELL_H / 2
INC_MAXX, INC_MAXY = INC_X + CELL_W, INC_Y + CELL_H


def build_svg() -> str:
    shadow_dy = 8.0
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <defs>
    <linearGradient id="paper" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="{PAPER_TOP}"/><stop offset="1" stop-color="{PAPER_BOTTOM}"/>
    </linearGradient>
    <linearGradient id="tray" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="{TRAY_TOP}"/><stop offset="1" stop-color="{TRAY_BOTTOM}"/>
    </linearGradient>
    <clipPath id="squircle">
      <rect x="{MARGIN}" y="{MARGIN}" width="{BASE - 2*MARGIN}" height="{BASE - 2*MARGIN}" rx="{SQUIRCLE_R}"/>
    </clipPath>
    <filter id="cardShadow" x="-30%" y="-30%" width="160%" height="160%">
      <feDropShadow dx="0" dy="{shadow_dy}" stdDeviation="{16/2}" flood-color="#191919" flood-opacity="0.14"/>
    </filter>
  </defs>
  <g clip-path="url(#squircle)">
    <!-- 纸面（上亮下微沉）+ 纸缘 hairline -->
    <rect x="{MARGIN}" y="{MARGIN}" width="{BASE - 2*MARGIN}" height="{BASE - 2*MARGIN}" fill="url(#paper)"/>
    <rect x="{MARGIN}" y="{MARGIN}" width="{BASE - 2*MARGIN}" height="{BASE - 2*MARGIN}" rx="{SQUIRCLE_R}"
          fill="none" stroke="{PAPER_EDGE}" stroke-width="5"/>
    <!-- 开口匣：渐变匣体 + 外缘 hairline（镂空区域由下一步直接覆盖，视觉同 even-odd） -->
    <rect x="{TRAY_X}" y="{TRAY_Y}" width="{TRAY_W}" height="{TRAY_H}" rx="{TRAY_R}" fill="url(#tray)"/>
    <rect x="{TRAY_X}" y="{TRAY_Y}" width="{TRAY_W}" height="{TRAY_H}" rx="{TRAY_R}"
          fill="none" stroke="{TRAY_EDGE}" stroke-width="6"/>
    <!-- 镂空底：沉一档纸色 + 顶部 34px 内阴影（匣口深度暗示） -->
    <rect x="{HOLE_X}" y="{HOLE_Y}" width="{HOLE_W}" height="{HOLE_H}" rx="{HOLE_R}" fill="{HOLE_FILL}"/>
    <clipPath id="holeClip"><rect x="{HOLE_X}" y="{HOLE_Y}" width="{HOLE_W}" height="{HOLE_H}" rx="{HOLE_R}"/></clipPath>
    <g clip-path="url(#holeClip)">
      <rect x="{HOLE_X}" y="{HOLE_Y}" width="{HOLE_W}" height="34" fill="#000000" fill-opacity="0.13"/>
    </g>
    <!-- 格架 2×2：三张象牙卡（左上/左下/右下），右上留空「还有下一格」 -->
    <rect x="{CX0}" y="{CY_TOP}" width="{CELL_W}" height="{CELL_H}" rx="{CELL_R}" fill="{CARD_FILL}" stroke="{CARD_EDGE}" stroke-width="4"/>
    <rect x="{CX0}" y="{CY_BOTTOM}" width="{CELL_W}" height="{CELL_H}" rx="{CELL_R}" fill="{CARD_FILL}" stroke="{CARD_EDGE}" stroke-width="4"/>
    <rect x="{CX1}" y="{CY_BOTTOM}" width="{CELL_W}" height="{CELL_H}" rx="{CELL_R}" fill="{CARD_FILL}" stroke="{CARD_EDGE}" stroke-width="4"/>
    <!-- 滑入炭卡：骑在匣顶缘、右偏、-10°、轻投影 -->
    <g transform="rotate({INCOMING_ANGLE} {INC_CX} {INC_CY})">
      <rect x="{INC_X}" y="{INC_Y}" width="{CELL_W}" height="{CELL_H}" rx="{CELL_R}"
            fill="{INCOMING}" filter="url(#cardShadow)"/>
    </g>
    <!-- 速度虚线 ×2（滑入反方向，右上；圆帽） -->
    <line x1="{INC_MAXX + 32}" y1="{INC_MAXY - 70}" x2="{INC_MAXX + 32 + 64}" y2="{INC_MAXY - 70 - 14}"
          stroke="{INCOMING}" stroke-opacity="0.24" stroke-width="9" stroke-linecap="round"/>
    <line x1="{INC_MAXX + 6}" y1="{INC_MAXY - 112}" x2="{INC_MAXX + 6 + 42}" y2="{INC_MAXY - 112 - 14}"
          stroke="{INCOMING}" stroke-opacity="0.13" stroke-width="8" stroke-linecap="round"/>
  </g>
</svg>
'''


def main() -> None:
    repo = Path(__file__).resolve().parent.parent
    out_dir = repo / "assets" / "icons"
    out_dir.mkdir(parents=True, exist_ok=True)
    svg_path = out_dir / "agentkeeper.svg"
    svg_path.write_text(build_svg())
    for size in (32, 64, 128, 256, 512):
        out = out_dir / f"agentkeeper-{size}.png"
        import subprocess
        subprocess.run(
            ["rsvg-convert", "-w", str(size), "-h", str(size), str(svg_path), "-o", str(out)],
            check=True,
        )
        print(f"rendered: {out.relative_to(repo)} ({size}x{size})")


if __name__ == "__main__":
    main()
