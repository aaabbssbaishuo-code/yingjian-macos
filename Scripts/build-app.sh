#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${1:-debug}"
APP_DIR="$ROOT_DIR/.build/英见.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
IDENTIFIER="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$ROOT_DIR/Resources/Info.plist")"
SIGNING_IDENTITY="${DEVELOPER_ID_APPLICATION:-}"

cd "$ROOT_DIR"
swift build -c "$CONFIGURATION"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$ROOT_DIR/.build/$CONFIGURATION/QuickLensTranslator" "$MACOS_DIR/QuickLensTranslator"
RUNTIME_LIBRARY="$ROOT_DIR/.build/$CONFIGURATION/libsherpa-onnx-c-api.dylib"
if [[ ! -f "$RUNTIME_LIBRARY" ]]; then
    echo "Missing sherpa-onnx runtime: $RUNTIME_LIBRARY" >&2
    exit 1
fi

if [[ "$(/usr/bin/lipo -info "$RUNTIME_LIBRARY")" == *"arm64"* ]]; then
    /usr/bin/lipo \
        "$RUNTIME_LIBRARY" \
        -thin arm64 \
        -output "$MACOS_DIR/libsherpa-onnx-c-api.dylib"
else
    cp "$RUNTIME_LIBRARY" "$MACOS_DIR/libsherpa-onnx-c-api.dylib"
fi
cp "$ROOT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$ROOT_DIR/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
cp "$ROOT_DIR/Resources/ThirdPartyNotices.txt" "$RESOURCES_DIR/ThirdPartyNotices.txt"

if [[ -n "$SIGNING_IDENTITY" ]]; then
    codesign \
        --force \
        --deep \
        --options runtime \
        --timestamp \
        --identifier "$IDENTIFIER" \
        --sign "$SIGNING_IDENTITY" \
        "$APP_DIR"
else
    codesign \
        --force \
        --deep \
        --identifier "$IDENTIFIER" \
        --sign - \
        "$APP_DIR"
fi

codesign --verify --deep --strict --verbose=2 "$APP_DIR"

echo "$APP_DIR"
