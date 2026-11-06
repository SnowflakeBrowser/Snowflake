#!/bin/bash
# Builds a release Veil.app in ./build. Requires macOS 13+ and Xcode (or Command Line Tools with Swift 5.9+).
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
BIN="$(swift build -c release --show-bin-path)/Veil"
APP="build/Veil.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Veil"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --deep --sign - "$APP"     # ad-hoc signature so Gatekeeper lets you run it locally
echo "Built $APP  (open build/Veil.app)"
