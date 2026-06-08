#!/usr/bin/env bash
set -euo pipefail

SETTINGS_PATH="${1:-$HOME/.claude/settings.json}"

if [ ! -f "$SETTINGS_PATH" ]; then
  echo "no settings file at $SETTINGS_PATH"
  exit 0
fi

python3 - "$SETTINGS_PATH" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as handle:
    raw = handle.read().strip()

settings = json.loads(raw) if raw else {}
hooks = settings.get("hooks", {})
changed = False
agent_light_markers = (
    "AgentClaudeHook",
    "claude-code-status-writer.sh",
)

for event, groups in list(hooks.items()):
    if not isinstance(groups, list):
        continue

    for group in groups:
        if not isinstance(group, dict):
            continue
        handlers = group.get("hooks", [])
        if not isinstance(handlers, list):
            continue

        kept = [
            handler
            for handler in handlers
            if not (
                isinstance(handler, dict)
                and isinstance(handler.get("command"), str)
                and any(marker in handler["command"] for marker in agent_light_markers)
            )
        ]
        if len(kept) != len(handlers):
            group["hooks"] = kept
            changed = True

    hooks[event] = [
        group
        for group in groups
        if not (isinstance(group, dict) and group.get("hooks") == [])
    ]

settings["hooks"] = {event: groups for event, groups in hooks.items() if groups}

if changed:
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(settings, handle, indent=2)
        handle.write("\n")

print("removed" if changed else "nothing to remove")
PY
