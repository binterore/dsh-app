#!/usr/bin/env bash
# 构建 DeepSeek.app —— 零第三方依赖的 macOS 原生桌面壳
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="DeepSeek"
BUILD_DIR="build"

echo "==> 清理旧构建产物"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "==> 编译 Swift 主程序"
swiftc -O Sources/main.swift -o "$BUILD_DIR/$APP_NAME"

echo "==> 生成图标（多尺寸 iconset → icns）"
ICONSET="$BUILD_DIR/AppIcon.iconset"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
    sips -z $s $s Assets/whale.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    s2=$((s * 2))
    sips -z $s2 $s2 Assets/whale.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$BUILD_DIR/AppIcon.icns"

echo "==> 组装 .app 包"
APP="$BUILD_DIR/$APP_NAME.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
cp Info.plist "$APP/Contents/Info.plist"
cp "$BUILD_DIR/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

echo "==> 代码签名（ad-hoc）"
codesign --force --deep --sign - "$APP"

echo "==> 完成：$APP"
echo "安装：cp -R \"$APP\" ~/Applications/"
