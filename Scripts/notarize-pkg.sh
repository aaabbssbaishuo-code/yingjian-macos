#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PKG_PATH="${1:-}"
KEYCHAIN_PROFILE="${NOTARY_KEYCHAIN_PROFILE:-yingjian-notary}"

if [[ -z "$PKG_PATH" || ! -f "$PKG_PATH" ]]; then
    echo "用法：$0 /path/to/yingjian-version.pkg" >&2
    exit 1
fi

xcrun notarytool submit \
    "$PKG_PATH" \
    --keychain-profile "$KEYCHAIN_PROFILE" \
    --wait

xcrun stapler staple "$PKG_PATH"
xcrun stapler validate "$PKG_PATH"
spctl --assess --type install --verbose=4 "$PKG_PATH"

if [[ "$(dirname "$PKG_PATH")" == "$ROOT_DIR/.build/dist" ]]; then
    ditto "$PKG_PATH" "$ROOT_DIR/.build/dist/yingjian-latest.pkg"
fi

echo "$PKG_PATH"
