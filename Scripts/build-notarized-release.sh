#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$ROOT_DIR/Resources/Info.plist")"
VERSIONED_PKG="$ROOT_DIR/.build/dist/yingjian-${VERSION}.pkg"

: "${DEVELOPER_ID_APPLICATION:?请设置 Developer ID Application 证书名称}"
: "${DEVELOPER_ID_INSTALLER:?请设置 Developer ID Installer 证书名称}"
: "${NOTARY_KEYCHAIN_PROFILE:=yingjian-notary}"
export DEVELOPER_ID_APPLICATION DEVELOPER_ID_INSTALLER NOTARY_KEYCHAIN_PROFILE

if ! security find-identity -v -p codesigning | grep -Fq "$DEVELOPER_ID_APPLICATION"; then
    echo "钥匙串中找不到应用签名证书：$DEVELOPER_ID_APPLICATION" >&2
    exit 1
fi

if ! security find-identity -v | grep -Fq "$DEVELOPER_ID_INSTALLER"; then
    echo "钥匙串中找不到安装包签名证书：$DEVELOPER_ID_INSTALLER" >&2
    exit 1
fi

"$ROOT_DIR/Scripts/build-app.sh" release
"$ROOT_DIR/Scripts/build-pkg.sh" "$ROOT_DIR/.build/英见.app" "yingjian-${VERSION}.pkg"
"$ROOT_DIR/Scripts/notarize-pkg.sh" "$VERSIONED_PKG"

pkgutil --check-signature "$VERSIONED_PKG"
spctl --assess --type install --verbose=4 "$ROOT_DIR/.build/dist/yingjian-latest.pkg"

echo "$VERSIONED_PKG"
echo "$ROOT_DIR/.build/dist/yingjian-latest.pkg"
