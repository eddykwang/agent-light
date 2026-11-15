#!/usr/bin/env bash
set -euo pipefail

: "${APPLE_TEAM_ID:?Set APPLE_TEAM_ID to the expected signing team}"
APP_BUNDLE="${1:?usage: verify_release.sh APP_BUNDLE}"
codesign --verify --deep --strict --verbose=4 "$APP_BUNDLE"
for target in "$APP_BUNDLE" \
  "$APP_BUNDLE/Contents/MacOS/AgentTrafficLights" \
  "$APP_BUNDLE/Contents/MacOS/AgentStatusCollector" \
  "$APP_BUNDLE/Contents/MacOS/AgentClaudeHook" \
  "$APP_BUNDLE/Contents/MacOS/AgentCopilotHook" \
  "$APP_BUNDLE/Contents/MacOS/AgentCodexHook"; do
  details="$(codesign --display --verbose=4 "$target" 2>&1)"
  printf '%s\n' "$details" | /usr/bin/grep -Fqx "TeamIdentifier=$APPLE_TEAM_ID"
  printf '%s\n' "$details" | /usr/bin/grep -q '^Authority=Developer ID Application:'
  printf '%s\n' "$details" | /usr/bin/grep -q '^Timestamp='
  printf '%s\n' "$details" | /usr/bin/grep -q 'flags=.*(runtime)'
done
xcrun stapler validate "$APP_BUNDLE"
spctl --assess --type execute --verbose=4 "$APP_BUNDLE"
# Public certificates embedded in signatures are expected; private material is not.
python3 "$(dirname "${BASH_SOURCE[0]}")/check_release_contents.py" "$APP_BUNDLE"
