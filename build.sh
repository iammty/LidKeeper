#!/bin/bash
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
SWIFT_FILE="$SRC_DIR/Sources/main.swift"
PLIST="$SRC_DIR/Resources/Info.plist"
BINARY="$SRC_DIR/LidKeeper"
APP_DIR="/Applications/LidKeeper.app"

echo "==> Building LidKeeper binary..."
swiftc -o "$BINARY" \
  -module-name LidKeeper \
  -framework Cocoa \
  -framework IOKit \
  "$SWIFT_FILE"

echo "==> Creating app bundle at $APP_DIR..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"
cp "$BINARY" "$APP_DIR/Contents/MacOS/LidKeeper"
cp "$PLIST" "$APP_DIR/Contents/Info.plist"

echo "==> Ad-hoc signing..."
codesign --force --sign - "$APP_DIR"

echo "==> Done. LidKeeper.app installed to /Applications."
echo "    Launch it from Finder or: open $APP_DIR"
