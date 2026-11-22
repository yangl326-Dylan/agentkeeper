#!/usr/bin/env bash
# GUI 冒烟：后台起 AgentKeeper 可执行 → 4s 判活 → 可选截图。
# 用法：scripts/smoke-linux-gui.sh [binary]
set -u

BIN="${1:-$(swift-build --show-bin-path 2>/dev/null)/AgentKeeper}"
if [ ! -x "$BIN" ]; then
    echo "binary not found: $BIN" >&2
    exit 1
fi

echo "smoke: $BIN"
"$BIN" >/tmp/ak-gui-smoke.log 2>&1 &
PID=$!
sleep 4

if kill -0 "$PID" 2>/dev/null; then
    echo "SMOKE-PASS: alive after 4s (pid $PID)"
    ALIVE=1
else
    echo "SMOKE-FAIL: process exited early"
    tail -20 /tmp/ak-gui-smoke.log
    exit 1
fi

# 可选截图（gnome-screenshot / ImageMagick import 任一可用即拍主窗口）
if command -v gnome-screenshot >/dev/null 2>&1; then
    gnome-screenshot -f docs/linux-gui-main-window.png 2>/dev/null && echo "screenshot: docs/linux-gui-main-window.png"
elif command -v import >/dev/null 2>&1; then
    import -window root docs/linux-gui-main-window.png 2>/dev/null && echo "screenshot: docs/linux-gui-main-window.png"
else
    echo "screenshot: no tool available (gnome-screenshot/import)"
fi

kill "$PID" 2>/dev/null
wait "$PID" 2>/dev/null
echo "smoke log: /tmp/ak-gui-smoke.log"
exit 0
