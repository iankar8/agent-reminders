#!/usr/bin/env bash
set -euo pipefail

# Build, install, and launch the Agent Reminders (WebView) menu bar app as a real
# /Applications app, so it can be opened from Spotlight/Launchpad/Finder and,
# optionally, started automatically at login.
#
# Usage:
#   ./script/build_and_run_web.sh            build + install to /Applications + launch
#   ./script/build_and_run_web.sh --install  build + install, don't launch
#   ./script/build_and_run_web.sh --login    install a Login Item so it starts at login
#   ./script/build_and_run_web.sh --unlogin  remove the Login Item
#   ./script/build_and_run_web.sh --verify   install + launch + confirm it's running

MODE="${1:-run}"

PRODUCT_NAME="AgentRemindersWeb"        # swift product + process name
APP_DISPLAY_NAME="Agent Reminders"      # .app bundle + Spotlight name
BUNDLE_ID="com.iankar.agentremindersweb"
MIN_SYSTEM_VERSION="13.0"
APP_VERSION="1.0"
BUILD_NUMBER="1"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PKG="$ROOT_DIR/apps/macos-web"

# Prefer /Applications; fall back to ~/Applications if it isn't writable.
INSTALL_DIR="/Applications"
[ -w "$INSTALL_DIR" ] || INSTALL_DIR="$HOME/Applications"
mkdir -p "$INSTALL_DIR"
APP_BUNDLE="$INSTALL_DIR/$APP_DISPLAY_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS="$CONTENTS/MacOS"
LAUNCH_AGENT="$HOME/Library/LaunchAgents/$BUNDLE_ID.plist"

install_login_item() {
  mkdir -p "$HOME/Library/LaunchAgents"
  cat >"$LAUNCH_AGENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$BUNDLE_ID</string>
  <key>ProgramArguments</key>
  <array><string>/usr/bin/open</string><string>$APP_BUNDLE</string></array>
  <key>RunAtLoad</key><true/>
</dict></plist>
PLIST
  launchctl unload "$LAUNCH_AGENT" >/dev/null 2>&1 || true
  launchctl load "$LAUNCH_AGENT"
  echo "Login item installed — Agent Reminders will start at login. Remove with: $0 --unlogin"
}

remove_login_item() {
  launchctl unload "$LAUNCH_AGENT" >/dev/null 2>&1 || true
  rm -f "$LAUNCH_AGENT"
  echo "Login item removed."
}

if [ "$MODE" = "--unlogin" ]; then remove_login_item; exit 0; fi

# --- build (release) ---
swift build --package-path "$PKG" -c release
BIN="$(swift build --package-path "$PKG" -c release --show-bin-path)"

# --- stage the .app into the install dir ---
pkill -x "$PRODUCT_NAME" >/dev/null 2>&1 || true
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS"
cp "$BIN/$PRODUCT_NAME" "$MACOS/$PRODUCT_NAME"
chmod +x "$MACOS/$PRODUCT_NAME"
cp -R "$BIN"/AgentRemindersWeb_*.bundle "$MACOS/" 2>/dev/null || true   # bundled panel.html

cat >"$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>$PRODUCT_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>$APP_DISPLAY_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_DISPLAY_NAME</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$APP_VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key><string>$MIN_SYSTEM_VERSION</string>
  <key>LSUIElement</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST

codesign --force --deep --sign - "$APP_BUNDLE" >/dev/null 2>&1 || true   # ad-hoc, local Gatekeeper

echo "Installed: $APP_BUNDLE"

case "$MODE" in
  run|"")
    open -n "$APP_BUNDLE"
    echo "Launched — look for the checklist icon in the menu bar."
    ;;
  --install)
    echo "Installed (not launched). Open it from Spotlight: \"$APP_DISPLAY_NAME\"."
    ;;
  --login)
    install_login_item
    open -n "$APP_BUNDLE"
    ;;
  --verify)
    open -n "$APP_BUNDLE"; sleep 1
    if pgrep -x "$PRODUCT_NAME" >/dev/null; then echo "VERIFY OK: running from $APP_BUNDLE"; else echo "VERIFY FAILED" >&2; exit 1; fi
    ;;
  *)
    echo "usage: $0 [run|--install|--login|--unlogin|--verify]" >&2; exit 2 ;;
esac
