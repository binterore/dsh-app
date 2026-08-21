#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

: "${DEVELOPER_ID_APPLICATION:?Set DEVELOPER_ID_APPLICATION to the Developer ID Application identity}"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to an xcrun notarytool keychain profile}"
: "${SPARKLE_PUBLIC_KEY:?Set SPARKLE_PUBLIC_KEY to the Ed25519 public key}"

if [[ "$SPARKLE_PUBLIC_KEY" == *REPLACE_WITH* ]]; then
  echo "Invalid SPARKLE_PUBLIC_KEY" >&2
  exit 1
fi
if ! xcodebuild -version >/dev/null 2>&1; then
  echo "A full Xcode installation is required for release builds." >&2
  exit 1
fi

VERSION="${MARKETING_VERSION:-2.0.0}"
BUILD_DIR="${BUILD_DIR:-build-release}"
BUILD_ARCHS="arm64 x86_64" \
CONFIGURATION=release \
BUNDLE_DSH_RUNTIME=1 \
SIGN_IDENTITY="$DEVELOPER_ID_APPLICATION" \
SPARKLE_PUBLIC_KEY="$SPARKLE_PUBLIC_KEY" \
MARKETING_VERSION="$VERSION" \
BUILD_DIR="$BUILD_DIR" \
./build.sh

APP="$BUILD_DIR/DeepSeek.app"
DMG="$BUILD_DIR/DeepSeek-$VERSION.dmg"
codesign -dv --verbose=4 "$APP"
spctl -a -vv --type execute "$APP"

echo "==> 公证 DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

GENERATE_APPCAST="$(find .build -type f -name generate_appcast -perm +111 | head -1)"
if [[ -z "$GENERATE_APPCAST" ]]; then
  echo "Sparkle generate_appcast not found." >&2
  exit 1
fi
mkdir -p "$BUILD_DIR/appcast-input"
cp "$DMG" "$BUILD_DIR/appcast-input/"
"$GENERATE_APPCAST" --download-url-prefix "https://github.com/binterore/dsh-app/releases/download/v$VERSION/" "$BUILD_DIR/appcast-input"
cp "$BUILD_DIR/appcast-input/appcast.xml" appcast.xml

echo "Release artifacts are notarized and the appcast has been signed."
