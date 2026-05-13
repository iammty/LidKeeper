#!/bin/bash
set -euo pipefail

APP_NAME="LidKeeper"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$SCRIPT_DIR/Sources/main.swift"
INFO="$SCRIPT_DIR/Resources/Info.plist"
APP_DIR="/Applications/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"

echo "==> Building $APP_NAME binary..."
swiftc \
    -o "$SCRIPT_DIR/$APP_NAME" \
    -module-name LidKeeper \
    -framework Cocoa \
    -framework CoreGraphics \
    "$SRC"

echo "==> Creating .app bundle at $APP_DIR..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS"

cp "$SCRIPT_DIR/$APP_NAME" "$MACOS/"
cp "$INFO" "$CONTENTS/"

codesign --force --sign - "$MACOS/$APP_NAME" 2>/dev/null || true

rm "$SCRIPT_DIR/$APP_NAME"

echo "==> Done! Installed to $APP_DIR"
echo ""
echo "  Launch:  open $APP_DIR"
echo ""
echo "  Boot autostart:"
echo "    mkdir -p ~/Library/LaunchAgents"
echo "    cp '$SCRIPT_DIR/com.lidkeeper.plist' ~/Library/LaunchAgents/"
echo "    launchctl load ~/Library/LaunchAgents/com.lidkeeper.plist"
