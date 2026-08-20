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
cp "$ROOT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$ROOT_DIR/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"

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
