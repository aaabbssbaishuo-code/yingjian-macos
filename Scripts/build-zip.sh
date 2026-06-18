#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="${1:-$ROOT_DIR/.build/英见.app}"
DIST_DIR="$ROOT_DIR/.build/dist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$ROOT_DIR/Resources/Info.plist")"
ZIP_NAME="${2:-英见-${VERSION}.zip}"

if [[ ! -d "$APP_PATH" ]]; then
    "$ROOT_DIR/Scripts/build-app.sh" release
fi

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$DIST_DIR/$ZIP_NAME"

echo "$DIST_DIR/$ZIP_NAME"
