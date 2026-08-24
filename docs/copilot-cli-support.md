# GitHub Copilot CLI Support

Agent Light supports local GitHub Copilot CLI sessions through Copilot's
official user-level lifecycle hooks. It does not support ordinary VS Code
Copilot chat, autocomplete, or Copilot cloud-agent jobs.

## Setup

Open **Settings... > Agents > Copilot CLI** and choose **Install**. Agent Light
creates one isolated configuration file:

```text
~/.copilot/hooks/agent-light.json
```

If `COPILOT_HOME` is present in Agent Light's process environment, the hook file
is written to `$COPILOT_HOME/hooks/agent-light.json` instead. Start a new
Copilot CLI session after installing, reinstalling, or removing hooks.

Agent Light does not install, authenticate, or update Copilot CLI itself. Use a
current Copilot CLI release that supports user-level hooks.

## Status Mapping

- A submitted prompt reports `working`.
- Actual permission prompts and elicitation dialogs report `needsInput`.
- The main-agent stop event reports `idle` and advances the completion marker.
- Explicit unrecoverable errors and error/timeout session endings report
  `failed`.
- Recoverable tool errors remain `working` because Copilot can retry or recover.

The installer intentionally does not register `preToolUse`: Copilot treats a
failed command hook there as a denial, so an old or moved Agent Light bundle
could otherwise block tools. It also does not use `permissionRequest` as an
attention signal because that event occurs before Copilot decides whether the
user must actually be prompted.

## Local State And Privacy

The bundled `AgentCopilotHook` writes one compact JSON file per session under:

```text
~/.agent-traffic-lights/copilot-hooks
```

Files contain only a session identifier, workspace path, status, short status
description, timestamps, and completion/end markers. Agent Light does not store
prompts, model responses, tool arguments, tool results, full error payloads, or
transcripts, and it does not call GitHub or any model API.

After a Copilot process exits, the last idle or failed state remains visible for
60 seconds so Agent Light's polling loop can observe short non-interactive runs.
Orphaned state that never receives a session-end event is pruned after 24 hours.

## Moving Or Removing Agent Light

The hook command contains the absolute path to `AgentCopilotHook` inside the app
bundle. If the app moves, Settings shows **Hooks need reinstalling**; choose
**Reinstall** to update that path.

Choose **Remove** to delete only Agent Light's `agent-light.json` hook and its
cached Copilot status files. Other Copilot hook files are never modified.
