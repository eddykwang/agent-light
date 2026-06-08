#!/usr/bin/env bash
set -euo pipefail

VERSION_INPUT="${1:-${GITHUB_REF_NAME:-0.1.3}}"
VERSION="${VERSION_INPUT#v}"
BUILD_NUMBER="${GITHUB_RUN_NUMBER:-1}"

PRODUCT_NAME="Agent Light"
EXECUTABLE_NAME="AgentTrafficLights"
BUNDLE_ID="com.agenttrafficlights.AgentTrafficLights"
MIN_SYSTEM_VERSION="14.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
RELEASE_DIR="$DIST_DIR/release"
APP_BUNDLE="$RELEASE_DIR/$PRODUCT_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$EXECUTABLE_NAME"
APP_ICON="$ROOT_DIR/Resources/AppIcon.icns"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ZIP_PATH="$DIST_DIR/Agent-Light-v$VERSION-macOS-unsigned.zip"

swift build -c release

BUILD_DIR="$(swift build -c release --show-bin-path)"
BUILD_BINARY="$BUILD_DIR/$EXECUTABLE_NAME"
COLLECTOR_BINARY="$BUILD_DIR/AgentStatusCollector"
CLAUDE_HOOK_BINARY="$BUILD_DIR/AgentClaudeHook"

rm -rf "$RELEASE_DIR"
mkdir -p "$APP_MACOS"
mkdir -p "$APP_RESOURCES"

cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
cp "$COLLECTOR_BINARY" "$APP_MACOS/AgentStatusCollector"
chmod +x "$APP_MACOS/AgentStatusCollector"
cp "$CLAUDE_HOOK_BINARY" "$APP_MACOS/AgentClaudeHook"
chmod +x "$APP_MACOS/AgentClaudeHook"
cp "$APP_ICON" "$APP_RESOURCES/AppIcon.icns"
cp -R "$ROOT_DIR/Resources/ProviderIcons" "$APP_RESOURCES/ProviderIcons"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$EXECUTABLE_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleName</key>
  <string>$PRODUCT_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$PRODUCT_NAME</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

# Ad-hoc signing keeps the bundle internally consistent for local execution, but
# it is not a trusted Developer ID signature and is intentionally not notarized.
codesign --force --deep --sign - "$APP_BUNDLE"
codesign --verify --deep --strict --verbose=4 "$APP_BUNDLE"

rm -f "$ZIP_PATH"
(
  cd "$RELEASE_DIR"
  ditto --norsrc --noextattr --noqtn --noacl -c -k --keepParent "$PRODUCT_NAME.app" "$ZIP_PATH"
)

echo "$ZIP_PATH"
