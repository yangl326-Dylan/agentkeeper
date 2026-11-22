#!/bin/bash
# 组装 Linux 分发产物：tar.gz（便携布局）与 .deb（Debian 包）。
# 用法: scripts/build-linux-app.sh [--deb|--targz|--all] [version]
#   version 缺省取 git describe --tags（无 tag 回退 0.0.0-dev）
# 产物: dist/agentkeeper-cli-linux-<ver>-x86_64.tar.gz（CLI only）或
#       dist/agentkeeper-gui-linux-<ver>-x86_64.tar.gz（含 GUI）与
#       dist/agentkeeper_<ver>_amd64.deb（.deb 恒含 CLI，GUI 二进制存在时自动纳入：
#       agentkeeper 可执行 + .desktop + hicolor 图标 + /usr/bin）
set -euo pipefail
cd "$(dirname "$0")/.."

MODE="${1:---all}"
VERSION="${2:-$(git describe --tags --abbrev=0 2>/dev/null || echo 0.0.0-dev)}"
VERSION="${VERSION#v}"
REPO_ROOT="$(pwd)"

SWIFT_BIN="${SWIFT_BIN:-swift}"
BUILD_ARGS=(--build-system native)

echo "== swift build (release, static stdlib) =="
"$SWIFT_BIN" build -c release --product ak --static-swift-stdlib "${BUILD_ARGS[@]}"
BIN_DIR="$("$SWIFT_BIN" build -c release --product ak --static-swift-stdlib "${BUILD_ARGS[@]}" --show-bin-path)"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/pkg" "$STAGE/deb/usr/bin" "$STAGE/deb/DEBIAN"
cp "$BIN_DIR/ak" "$STAGE/pkg/ak"
chmod 0755 "$STAGE/pkg/ak"

# GUI 二进制：存在则纳入（add-linux-app 交付后自动生效）
AK_APP_BIN="$(find .build -path "*release*" -name AgentKeeper -type f 2>/dev/null | head -1 || true)"
HAS_APP=0
if [ -n "$AK_APP_BIN" ]; then
    cp "$AK_APP_BIN" "$STAGE/pkg/agentkeeper"
    chmod 0755 "$STAGE/pkg/agentkeeper"
    HAS_APP=1
fi

# README 附带（安装/系统依赖说明）
cat > "$STAGE/pkg/README-linux.md" <<EOF
# AgentKeeper Linux (${VERSION})

## 系统依赖
- glibc（Ubuntu 24.04+ 自带）
- libsqlite3（通常自带；缺失: sudo apt-get install -y libsqlite3-0）
- GUI（如包含 agentkeeper 二进制）: libgtk-3-0, libayatana-appindicator3-1

## 安装
sudo install -m 0755 ak /usr/local/bin/ak
ak doctor
EOF

mkdir -p dist

if [ "$MODE" = "--targz" ] || [ "$MODE" = "--all" ]; then
    # 含 GUI 时命名为 gui 包（发布矩阵区分 CLI-only / 便携 GUI+CLI）
    if [ "$HAS_APP" = "1" ]; then
        OUT="dist/agentkeeper-gui-linux-${VERSION}-x86_64.tar.gz"
    else
        OUT="dist/agentkeeper-cli-linux-${VERSION}-x86_64.tar.gz"
    fi
    (cd "$STAGE/pkg" && tar -czf "$REPO_ROOT/$OUT" .)
    echo "built: $OUT"
fi

if [ "$MODE" = "--deb" ] || [ "$MODE" = "--all" ]; then
    cp "$STAGE/pkg/ak" "$STAGE/deb/usr/bin/ak"
    if [ "$HAS_APP" = "1" ]; then
        cp "$STAGE/pkg/agentkeeper" "$STAGE/deb/usr/bin/agentkeeper"
        # 图标：五档 hicolor（32/64/128/256/512；与 macOS AppIcon 同源——
        # assets/icons 由 scripts/gen-icon-linux.py 从 gen-icon.swift 几何复刻）
        for size in 32x32 64x64 128x128 256x256 512x512; do
            mkdir -p "$STAGE/deb/usr/share/icons/hicolor/$size/apps"
            src="assets/icons/agentkeeper-${size%%x*}.png"
            [ -f "$src" ] && cp "$src" "$STAGE/deb/usr/share/icons/hicolor/$size/apps/agentkeeper.png"
        done
        mkdir -p "$STAGE/deb/usr/share/applications"
        cat > "$STAGE/deb/usr/share/applications/agentkeeper.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=AgentKeeper
Comment=跨 agent 的 skill 管理器
Exec=/usr/bin/agentkeeper
Icon=agentkeeper
Terminal=false
Categories=Development;
EOF
    fi
    cat > "$STAGE/deb/DEBIAN/control" <<EOF
Package: agentkeeper
Version: ${VERSION}
Section: devel
Priority: optional
Architecture: amd64
Maintainer: yangl326-Dylan <yangl326@gmail.com>
Depends: libsqlite3-0$( [ "$HAS_APP" = "1" ] && echo ", libgtk-3-0, libayatana-appindicator3-1" )
Description: 跨 agent 的 skill 管理器（ak CLI$( [ "$HAS_APP" = "1" ] && echo " + GUI" )）
 统一编目本机所有 AI agent 的 skill 目录：作用域判定、同名漂移检测、停用/恢复/快照与分发。
EOF
    dpkg-deb --build --root-owner-group "$STAGE/deb" "dist/agentkeeper_${VERSION}_amd64.deb" > /dev/null
    echo "built: dist/agentkeeper_${VERSION}_amd64.deb"
fi

echo "done (version=${VERSION}, app=${HAS_APP})"
