#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

echo "Building release binary…"
swift build -c release

BIN_PATH="$(swift build -c release --show-bin-path)"
APP="build/Attention Stack.app"

echo "Assembling app bundle…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp "$BIN_PATH/AttentionStack" "$APP/Contents/MacOS/AttentionStack"
cp "Info.plist" "$APP/Contents/Info.plist"

echo "Ad-hoc signing…"
codesign --force --deep --sign - "$APP"

echo "Done: $APP"
