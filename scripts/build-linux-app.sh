#!/bin/bash
# 组装 Linux 分发产物：tar.gz（便携布局）与 .deb（Debian 包）。
# 用法: scripts/build-linux-app.sh [--deb|--targz|--all] [version]
#   version 缺省取 git describe --tags（无 tag 回退 0.0.0-dev）
# 产物: dist/agentkeeper-cli-linux-<ver>-x86_64.tar.gz 与/或 dist/agentkeeper_<ver>_amd64.deb
# 说明: 现阶段 CLI only；Linux GUI 产物（agentkeeper 二进制 + .desktop + 图标）在
#       openspec change add-linux-app 交付后由本脚本自动纳入（检测 .build 产物存在即打包）。
set -euo pipefail
cd "$(dirname "$0")/.."

MODE="${1:---all}"
VERSION="${2:-$(git describe --tags --abbrev=0 2>/dev/null || echo 0.0.0-dev)}"
VERSION="${VERSION#v}"

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
- GUI（如包含 agentkeeper 二进制）: libgtk-4-1

## 安装
sudo install -m 0755 ak /usr/local/bin/ak
ak doctor
EOF

mkdir -p dist

if [ "$MODE" = "--targz" ] || [ "$MODE" = "--all" ]; then
    OUT="dist/agentkeeper-cli-linux-${VERSION}-x86_64.tar.gz"
    (cd "$STAGE/pkg" && tar -czf "/mnt/data/code/agentkeeper/$OUT" .)
    echo "built: $OUT"
fi

if [ "$MODE" = "--deb" ] || [ "$MODE" = "--all" ]; then
    cp "$STAGE/pkg/ak" "$STAGE/deb/usr/bin/ak"
    if [ "$HAS_APP" = "1" ]; then
        cp "$STAGE/pkg/agentkeeper" "$STAGE/deb/usr/bin/agentkeeper"
        mkdir -p "$STAGE/deb/usr/share/applications" "$STAGE/deb/usr/share/icons/hicolor/256x256/apps"
        cat > "$STAGE/deb/usr/share/applications/agentkeeper.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=AgentKeeper
Comment=跨 agent 的 skill 管理器
Exec=/usr/bin/agentkeeper
Icon=agentkeeper
Terminal=false
Categories=Development;Utility;
EOF
        if [ -f assets/icons/agentkeeper-256.png ]; then
            cp assets/icons/agentkeeper-256.png "$STAGE/deb/usr/share/icons/hicolor/256x256/apps/agentkeeper.png"
        fi
    fi
    cat > "$STAGE/deb/DEBIAN/control" <<EOF
Package: agentkeeper
Version: ${VERSION}
Section: devel
Priority: optional
Architecture: amd64
Maintainer: yangl326-Dylan <yangl326@gmail.com>
Depends: libsqlite3-0$( [ "$HAS_APP" = "1" ] && echo ", libgtk-4-1" )
Description: 跨 agent 的 skill 管理器（ak CLI$( [ "$HAS_APP" = "1" ] && echo " + GUI" )）
 统一编目本机所有 AI agent 的 skill 目录：作用域判定、同名漂移检测、停用/恢复/快照与分发。
EOF
    dpkg-deb --build --root-owner-group "$STAGE/deb" "dist/agentkeeper_${VERSION}_amd64.deb" > /dev/null
    echo "built: dist/agentkeeper_${VERSION}_amd64.deb"
fi

echo "done (version=${VERSION}, app=${HAS_APP})"
