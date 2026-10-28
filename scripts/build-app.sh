#!/bin/bash
# 组装 AgentKeeper.app（LaunchServices 正确注册：Dock 图标 + 应用菜单栏 + ⌘Tab）。
# 用法: scripts/build-app.sh [debug|release]   → 产出 ./AgentKeeper.app
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-debug}"
swift build -c "$CONFIG"

APP="AgentKeeper.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
cp "$BIN_DIR/AgentKeeper" "$APP/Contents/MacOS/AgentKeeper"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>AgentKeeper</string>
    <key>CFBundleDisplayName</key><string>AgentKeeper</string>
    <key>CFBundleIdentifier</key><string>app.agentkeeper.mac</string>
    <key>CFBundleExecutable</key><string>AgentKeeper</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>LSUIElement</key><false/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

# 本地 ad-hoc 签名（Gatekeeper 无提示；分发需正式签名）
codesign --force --sign - "$APP" >/dev/null 2>&1 || true

echo "built: $APP"
