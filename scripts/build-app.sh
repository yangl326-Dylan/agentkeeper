#!/bin/bash
# 组装 AgentKeeper.app（LaunchServices 正确注册：Dock 图标 + 应用菜单栏 + ⌘Tab）。
# 用法: scripts/build-app.sh [debug|release]   → 产出 ./AgentKeeper.app
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-debug}"
# UNIVERSAL=1:构建 arm64+x86_64 双架构产物(发布用;本地默认走原生单架构更快)
ARCH_FLAGS=()
if [ "${UNIVERSAL:-0}" = "1" ]; then
    ARCH_FLAGS=(--arch arm64 --arch x86_64)
fi
swift build -c "$CONFIG" "${ARCH_FLAGS[@]}"

# 图标：引导页同款「带箭头的箱子」+ Claude 色系（母版变更时重生成）
if [ ! -f build/AppIcon.icns ] || [ scripts/gen-icon.swift -nt build/AppIcon.icns ]; then
    mkdir -p build
    swift scripts/gen-icon.swift
    iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
fi

APP="AgentKeeper.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

BIN_DIR="$(swift build -c "$CONFIG" "${ARCH_FLAGS[@]}" --show-bin-path)"
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
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIconName</key><string>AppIcon</string>
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
