#!/usr/bin/env bash
# 构建 DeepSeek.app —— 零第三方依赖的 macOS 原生桌面壳
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="DeepSeek"
BUILD_DIR="build"

echo "==> 清理旧构建产物"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "==> 应用 DSH 补丁（tool 消息顺序 / 图片模型切换 / full-access schema）"
# 补丁脚本幂等：已打过的自动跳过；打不了（DSH 未安装或版本漂移）只告警，不阻断构建。
for patch in scripts/fix-dsh-tool-result-order.sh scripts/fix-dsh-image-model-switch.sh scripts/fix-dsh-full-access-schema.sh; do
    if ! "$patch"; then
        echo "⚠️  补丁失败（DSH 未安装或版本已变更？）：$patch" >&2
    fi
done

echo "==> 编译 Swift 主程序（兼容 macOS 13.0+）"
swiftc -O -target arm64-apple-macosx13.0 Sources/*.swift -o "$BUILD_DIR/$APP_NAME"

echo "==> 生成图标（裁掉透明留白，多尺寸 iconset → icns）"
ICONSET="$BUILD_DIR/AppIcon.iconset"
ICON_SOURCE="$BUILD_DIR/AppIcon-source.png"
mkdir -p "$ICONSET"
# 原图主体仅占 880×649 px；先把 1024 px 透明画布居中裁成 880 px，
# 避免 macOS 再按整张画布缩放后，Dock 中的鲸鱼明显小于相邻图标。
sips -c 880 880 Assets/whale.png --out "$ICON_SOURCE" >/dev/null
for s in 16 32 128 256 512; do
    sips -z $s $s "$ICON_SOURCE" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    s2=$((s * 2))
    sips -z $s2 $s2 "$ICON_SOURCE" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
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
