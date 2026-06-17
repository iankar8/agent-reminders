#!/usr/bin/env bash
set -euo pipefail

# Build, stage, and run the Agent Reminders menu bar app.
# SwiftPM SwiftUI GUI app, staged as a real .app bundle and launched with `open -n`.
# Follows the Codex build-macos-apps run-button bootstrap contract.
#
# Usage: ./script/build_and_run.sh [run|--debug|--logs|--telemetry|--verify]

MODE="${1:-run}"

PRODUCT_NAME="AgentReminders"          # swift build product + process name (pgrep)
APP_DISPLAY_NAME="Agent Reminders"     # .app bundle folder + CFBundleName
BUNDLE_ID="com.iankar.agentreminders"
MIN_SYSTEM_VERSION="13.0"
APP_VERSION="1.0"
BUILD_NUMBER="142"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_DIR="$ROOT_DIR/apps/macos"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_DISPLAY_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_BINARY="$APP_MACOS/$PRODUCT_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"

# 1. Stop the running app if present.
pkill -x "$PRODUCT_NAME" >/dev/null 2>&1 || true

# 2. Build the SwiftPM product.
swift build --package-path "$PACKAGE_DIR"
BUILD_BINARY="$(swift build --package-path "$PACKAGE_DIR" --show-bin-path)/$PRODUCT_NAME"

# 3. Stage dist/Agent Reminders.app
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$PRODUCT_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_DISPLAY_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_DISPLAY_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

# 4. Act on the mode.
case "$MODE" in
  run)
    open_app
    echo "Launched \"$APP_DISPLAY_NAME\" — look for the checklist icon in the menu bar."
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$PRODUCT_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    if pgrep -x "$PRODUCT_NAME" >/dev/null; then
      echo "VERIFY OK: $PRODUCT_NAME running; bundle staged at $APP_BUNDLE"
    else
      echo "VERIFY FAILED: $PRODUCT_NAME not running after launch (needs a logged-in GUI session)" >&2
      exit 1
    fi
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
