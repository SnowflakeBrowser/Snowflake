#!/bin/bash
# Builds the installer files for GitHub: dist/Veil-<version>.dmg and dist/Veil-<version>.zip
# Run on a Mac:   ./scripts/make_dmg.sh 1.0.0
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${1:-${VERSION:-1.0.0}}"

./scripts/build_app.sh
APP="build/Veil.app"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$APP/Contents/Info.plist" 2>/dev/null || true
codesign --force --deep --sign - "$APP"          # re-sign after editing the version

rm -rf dist && mkdir -p dist
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/Veil.app"
ln -s /Applications "$STAGE/Applications"        # lets people drag Veil onto Applications
hdiutil create -volname "Veil" -srcfolder "$STAGE" -ov -format UDZO "dist/Veil-$VERSION.dmg"
ditto -c -k --keepParent "$APP" "dist/Veil-$VERSION.zip"
rm -rf "$STAGE"
echo "Created dist/Veil-$VERSION.dmg and dist/Veil-$VERSION.zip"
