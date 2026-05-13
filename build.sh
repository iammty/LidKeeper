#!/bin/bash
set -euo pipefail

APP_NAME="LidKeeper"
BUNDLE_ID="com.matengyu.lidkeeper"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_SWIFT="$SCRIPT_DIR/Sources/main.swift"
SRC_C="$SCRIPT_DIR/Sources/pm_helper.c"
INFO="$SCRIPT_DIR/Resources/Info.plist"
APP_DIR="/Applications/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"

echo "==> Building $APP_NAME binary..."
swiftc \
    -o "$SCRIPT_DIR/$APP_NAME" \
    -module-name LidKeeper \
    -framework Cocoa \
    -framework IOKit \
    "$SRC_SWIFT" \
    "$SRC_C"

echo "==> Creating .app bundle at $APP_DIR..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS"

cp "$SCRIPT_DIR/$APP_NAME" "$MACOS/"
cp "$INFO" "$CONTENTS/"

# Ad-hoc sign (no Apple Developer account needed for local use)
codesign --force --sign - "$MACOS/$APP_NAME" 2>/dev/null || true

rm "$SCRIPT_DIR/$APP_NAME"

echo "==> Done! Installed to $APP_DIR"
echo ""
echo "  Launch it:  open $APP_DIR"
echo ""
echo "  For boot autostart:"
echo "    mkdir -p ~/Library/LaunchAgents"
echo "    cp '$SCRIPT_DIR/com.lidkeeper.plist' ~/Library/LaunchAgents/"
echo "    launchctl load ~/Library/LaunchAgents/com.lidkeeper.plist"
