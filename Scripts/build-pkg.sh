#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="${1:-$ROOT_DIR/.build/英见.app}"
DIST_DIR="$ROOT_DIR/.build/dist"
STAGING_DIR="$(mktemp -d "$ROOT_DIR/.build/pkgroot.XXXXXX")"
SCRIPTS_DIR="$ROOT_DIR/Scripts/pkg"
IDENTIFIER="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$ROOT_DIR/Resources/Info.plist")"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$ROOT_DIR/Resources/Info.plist")"
PKG_NAME="${2:-英见-${VERSION}.pkg}"

cleanup() {
    rm -rf "$STAGING_DIR" >/dev/null 2>&1 || true
}
trap cleanup EXIT

if [[ ! -d "$APP_PATH" ]]; then
    "$ROOT_DIR/Scripts/build-app.sh" release
fi

rm -rf "$DIST_DIR"
mkdir -p "$STAGING_DIR/Applications" "$DIST_DIR"

cp -R "$APP_PATH" "$STAGING_DIR/Applications/英见.app"

pkgbuild \
    --root "$STAGING_DIR" \
    --install-location "/" \
    --scripts "$SCRIPTS_DIR" \
    --identifier "$IDENTIFIER" \
    --version "$VERSION" \
    "$DIST_DIR/$PKG_NAME"

echo "$DIST_DIR/$PKG_NAME"
