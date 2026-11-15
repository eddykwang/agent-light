#!/usr/bin/env bash
set -euo pipefail

VERSION_INPUT="${1:-${GITHUB_REF_NAME:?Pass a new release version}}"
VERSION="${VERSION_INPUT#v}"
BUILD_NUMBER="${GITHUB_RUN_NUMBER:-1}"

: "${SIGNING_IDENTITY:?Set SIGNING_IDENTITY to your Developer ID Application identity}"
: "${APPLE_TEAM_ID:?Set APPLE_TEAM_ID to your signing team}"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to a notarytool Keychain profile}"
[[ "$SIGNING_IDENTITY" == "Developer ID Application: "* ]] || { echo "Developer ID Application identity required" >&2; exit 1; }
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$BUILD_NUMBER" =~ ^[0-9]+$ ]] || { echo "Invalid version/build number" >&2; exit 1; }
[[ "$APPLE_TEAM_ID" =~ ^[A-Z0-9]{10}$ ]] || { echo "Invalid Apple Team ID" >&2; exit 1; }
NOTARY_ARGS=(--keychain-profile "$NOTARY_PROFILE")
if [[ -n "${NOTARY_KEYCHAIN:-}" ]]; then
  NOTARY_ARGS+=(--keychain "$NOTARY_KEYCHAIN")
fi
# Check authentication before building, without exposing stored credentials.
xcrun notarytool history "${NOTARY_ARGS[@]}" >/dev/null

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
DESKTOP_LIGHT_ASSETS="$ROOT_DIR/Resources/DesktopLightAssets"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ZIP_PATH="$DIST_DIR/Agent-Light-v$VERSION-macOS.zip"

swift build -c release

BUILD_DIR="$(swift build -c release --show-bin-path)"
BUILD_BINARY="$BUILD_DIR/$EXECUTABLE_NAME"
COLLECTOR_BINARY="$BUILD_DIR/AgentStatusCollector"
CLAUDE_HOOK_BINARY="$BUILD_DIR/AgentClaudeHook"
COPILOT_HOOK_BINARY="$BUILD_DIR/AgentCopilotHook"

rm -rf "$RELEASE_DIR"
mkdir -p "$APP_MACOS"
mkdir -p "$APP_RESOURCES"

cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
cp "$COLLECTOR_BINARY" "$APP_MACOS/AgentStatusCollector"
chmod +x "$APP_MACOS/AgentStatusCollector"
cp "$CLAUDE_HOOK_BINARY" "$APP_MACOS/AgentClaudeHook"
chmod +x "$APP_MACOS/AgentClaudeHook"
cp "$COPILOT_HOOK_BINARY" "$APP_MACOS/AgentCopilotHook"
chmod +x "$APP_MACOS/AgentCopilotHook"
cp "$APP_ICON" "$APP_RESOURCES/AppIcon.icns"
cp -R "$ROOT_DIR/Resources/ProviderIcons" "$APP_RESOURCES/ProviderIcons"
cp -R "$DESKTOP_LIGHT_ASSETS" "$APP_RESOURCES/DesktopLightAssets"

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

python3 "$ROOT_DIR/script/check_release_contents.py" "$APP_BUNDLE"
for helper in AgentStatusCollector AgentClaudeHook AgentCopilotHook; do
  codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$APP_MACOS/$helper"
done
codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$APP_BUNDLE"
codesign --verify --deep --strict --verbose=4 "$APP_BUNDLE"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT
ditto -c -k --keepParent "$APP_BUNDLE" "$WORK_DIR/submission.zip"
submit_exit=0
xcrun notarytool submit "$WORK_DIR/submission.zip" "${NOTARY_ARGS[@]}" \
  --wait --timeout 30m --output-format json >"$WORK_DIR/notary.json" || submit_exit=$?
python3 - "$WORK_DIR/notary.json" <<'PY'
import json, sys
result = json.load(open(sys.argv[1]))
print("Notarization:", result.get("id"), result.get("status"))
if result.get("status") != "Accepted":
    sys.exit("Notarization not accepted; query this submission with notarytool info/log before retrying")
PY
[[ "$submit_exit" == 0 ]] || exit "$submit_exit"
xcrun stapler staple "$APP_BUNDLE"
xcrun stapler validate "$APP_BUNDLE"
# Repack after stapling; only the verified final archive can enter dist/.
ditto -c -k --keepParent "$APP_BUNDLE" "$WORK_DIR/final.zip"
ditto -x -k "$WORK_DIR/final.zip" "$WORK_DIR/verify"
bash "$ROOT_DIR/script/verify_release.sh" "$WORK_DIR/verify/$PRODUCT_NAME.app"
mv -f "$WORK_DIR/final.zip" "$ZIP_PATH"

echo "$ZIP_PATH"
