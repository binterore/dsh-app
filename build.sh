#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="DeepSeek"
BUILD_DIR="${BUILD_DIR:-build}"
CONFIGURATION="${CONFIGURATION:-release}"
BUILD_ARCHS="${BUILD_ARCHS:-arm64}"
BUNDLE_DSH_RUNTIME="${BUNDLE_DSH_RUNTIME:-1}"
MARKETING_VERSION="${MARKETING_VERSION:-2.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 20000)}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
SPARKLE_FEED_URL="${SPARKLE_FEED_URL:-https://raw.githubusercontent.com/binterore/dsh-app/main/appcast.xml}"
SPARKLE_PUBLIC_KEY="${SPARKLE_PUBLIC_KEY:-REPLACE_WITH_SPARKLE_ED25519_PUBLIC_KEY}"

case "$BUILD_DIR" in
  ""|"/"|"$HOME")
    echo "Refusing unsafe BUILD_DIR: $BUILD_DIR" >&2
    exit 1
    ;;
esac

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

SWIFT_ARGS=(--configuration "$CONFIGURATION")
for arch in $BUILD_ARCHS; do
  SWIFT_ARGS+=(--arch "$arch")
done

echo "==> 构建 SwiftPM App（${CONFIGURATION} / ${BUILD_ARCHS}）"
swift build "${SWIFT_ARGS[@]}"
BIN_DIR="$(swift build "${SWIFT_ARGS[@]}" --show-bin-path)"

echo "==> 生成应用图标"
ICONSET="$BUILD_DIR/AppIcon.iconset"
ICON_SOURCE="$BUILD_DIR/AppIcon-source.png"
mkdir -p "$ICONSET"
sips -c 880 880 Assets/whale.png --out "$ICON_SOURCE" >/dev/null
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$ICON_SOURCE" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  retina=$((size * 2))
  sips -z "$retina" "$retina" "$ICON_SOURCE" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$BUILD_DIR/AppIcon.icns"

APP="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP/Contents"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources" "$CONTENTS/Frameworks"
cp "$BIN_DIR/DeepSeek" "$CONTENTS/MacOS/$APP_NAME"
if ! otool -l "$CONTENTS/MacOS/$APP_NAME" | grep -q '@executable_path/../Frameworks'; then
  install_name_tool -add_rpath '@executable_path/../Frameworks' "$CONTENTS/MacOS/$APP_NAME"
fi
cp "$BUILD_DIR/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"
cp Info.plist "$CONTENTS/Info.plist"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $MARKETING_VERSION" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :SUFeedURL $SPARKLE_FEED_URL" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :SUPublicEDKey $SPARKLE_PUBLIC_KEY" "$CONTENTS/Info.plist"

if [[ -d "$BIN_DIR/Sparkle.framework" ]]; then
  echo "==> 嵌入 Sparkle.framework"
  ditto "$BIN_DIR/Sparkle.framework" "$CONTENTS/Frameworks/Sparkle.framework"
else
  echo "Sparkle.framework not found in $BIN_DIR" >&2
  exit 1
fi

if [[ "$BUNDLE_DSH_RUNTIME" == "1" ]]; then
  echo "==> 安装固定 DSH 运行时 0.1.0-rc.7"
  RUNTIME_BUILD="$BUILD_DIR/dsh-runtime"
  mkdir -p "$RUNTIME_BUILD"
  cp Runtime/package.json Runtime/package-lock.json "$RUNTIME_BUILD/"
  npm ci --prefix "$RUNTIME_BUILD" --omit=dev --ignore-scripts --offline 2>/dev/null || \
    npm ci --prefix "$RUNTIME_BUILD" --omit=dev --ignore-scripts

  runtime_real="$(cd "$RUNTIME_BUILD" && pwd -P)"
  build_real="$(cd "$BUILD_DIR" && pwd -P)"
  if [[ "$runtime_real" != "$build_real"/* ]]; then
    echo "Refusing to patch runtime outside build directory: $runtime_real" >&2
    exit 1
  fi
  for patch in \
    scripts/fix-dsh-tool-result-order.sh \
    scripts/fix-dsh-image-model-switch.sh \
    scripts/fix-dsh-full-access-schema.sh \
    scripts/fix-dsh-chunk-serialization.sh; do
    "$patch" --dsh-root "$runtime_real" --no-backup
  done
  ditto "$RUNTIME_BUILD" "$CONTENTS/Resources/dsh-runtime"
else
  echo "==> 跳过内置 DSH；开发构建会使用固定版本 npx fallback"
fi

echo "==> 签名应用"
SIGN_ARGS=(--force --deep --sign "$SIGN_IDENTITY" --entitlements DeepSeek.entitlements)
if [[ "$SIGN_IDENTITY" != "-" ]]; then
  SIGN_ARGS+=(--options runtime --timestamp)
fi
codesign "${SIGN_ARGS[@]}" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "==> 生成 DMG"
DMG="$BUILD_DIR/DeepSeek-$MARKETING_VERSION.dmg"
hdiutil create -volname "DeepSeek Desktop" -srcfolder "$APP" -ov -format UDZO "$DMG" >/dev/null

echo "Build complete: $APP"
echo "DMG: $DMG"
