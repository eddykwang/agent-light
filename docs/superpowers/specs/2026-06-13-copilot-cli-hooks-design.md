# Copilot CLI Hooks Support Design

Date: 2026-06-13

## Goal

Add first-class GitHub Copilot CLI status support to Agent Light through local
Copilot CLI hooks. The feature should mirror the existing Claude Code hooks
experience where it makes sense, while keeping each agent's hook integration
isolated so future provider changes do not disturb working integrations.

This design covers Copilot CLI only. It does not promise support for ordinary
VS Code Copilot chat, VS Code Copilot agent sessions, Copilot autocomplete, or
Copilot cloud agent sessions unless those surfaces emit the same local Copilot
CLI hook events.

## Scope

In scope:

- Add a dedicated bundled helper executable named `AgentCopilotHook`.
- Add a Copilot CLI hook event mapper in `AgentTrafficLightsCore`.
- Add a collector source that reads compact Copilot hook status files.
- Add manual install/remove controls for Copilot CLI hooks.
- Replace the top-level Settings "Claude Code" area with an "Agents" area that
  contains tabs for Claude Code and Copilot CLI.
- Update onboarding so agent hook setup lives under an "Agents" step with tabs.
- Package the new helper in the app bundle and add focused tests.

Out of scope:

- Reading VS Code extension internals.
- Calling GitHub, Copilot, or any model API.
- Capturing prompts, tool inputs, or model responses.
- Migrating or renaming the existing `AgentClaudeHook` integration.
- Automatically installing Copilot hooks without user action.

## Architecture

Copilot support should follow the existing three-part hook pattern:

1. `AgentCopilotHook` receives Copilot CLI hook JSON on stdin and writes compact
   local status metadata.
2. `CopilotHookSource` reads those status files and emits `RawSession` values
   with provider `copilot-cli`.
3. `CopilotHookInstaller` installs or removes Agent Light hook entries from the
   Copilot CLI user-level hook configuration.

Claude Code remains independent. The existing `AgentClaudeHook`,
`ClaudeHookEventMapper`, `ClaudeCodeHookSource`, and `ClaudeHookInstaller` stay
provider-specific. Shared code may be extracted only when it is small, obvious,
and does not change existing Claude Code behavior.

The packaged app bundle must include:

```text
Agent Light.app/Contents/MacOS/AgentTrafficLights
Agent Light.app/Contents/MacOS/AgentStatusCollector
Agent Light.app/Contents/MacOS/AgentClaudeHook
Agent Light.app/Contents/MacOS/AgentCopilotHook
```

## Data Flow

Copilot CLI runs an Agent Light command hook during lifecycle events. The hook
command invokes the bundled `AgentCopilotHook` helper. The helper parses stdin,
maps the event into `AgentStatus`, and writes one compact JSON file per session:

```text
~/.agent-traffic-lights/copilot-hooks/<session-id>.json
```

The compact status file stores only:

- session id
- status
- short detail string
- workspace path
- optional session or transcript path if Copilot provides one
- updated timestamp
- optional completed timestamp

The collector reads Copilot hook files when Copilot hooks are enabled, treats
them as event signals, merges them with other providers, and writes the shared
status snapshot at `~/.agent-traffic-lights/status.json`.

`SessionEnd` removes the hook status file so completed sessions do not linger.
Old orphaned files are pruned by `CopilotHookSource`, matching the Claude hook
source behavior.

## Status Mapping

Copilot CLI status semantics should match Claude Code hooks:

- session start, prompt submitted, and tool events -> `working`
- permission or input request events -> `needsInput`
- relevant permission/input notification events -> `needsInput`
- turn completion events -> `idle` and set `completedAt`
- session end events -> remove the compact status file
- explicit failure events -> `failed`
- unknown active lifecycle events -> `working`
- noisy informational events -> no state change

The mapper should be conservative about alerts. It should only emit
`needsInput` when the event clearly means the user must respond. If Copilot's
payload names differ from Claude's, the mapper may support explicit fallback
keys for event name, session id, and workspace path, but tests must document the
accepted field names.

## Settings UI

The Settings sidebar item currently dedicated to Claude Code becomes
`Agents`. The Agents pane contains a tab or segmented control with one tab per
agent:

- `Claude Code`
- `Copilot CLI`

The Claude Code tab preserves the existing behavior: mode comparison,
Transcript/Hooks selection, install/remove buttons, install status, privacy
copy, and restart/new-session guidance.

The Copilot CLI tab includes:

- a short explanation of Copilot CLI hooks
- install/remove buttons
- install status
- privacy copy stating that Agent Light stores only status metadata locally
- guidance that existing Copilot CLI sessions should be restarted or replaced
  with new sessions after installing or removing hooks

Future agent integrations should be added as tabs inside Agents instead of new
top-level Settings sidebar items.

## Onboarding UI

The onboarding step that currently focuses on Claude Code hook setup becomes an
Agents setup step. It uses the same tab model as Settings:

- `Claude Code` tab for the existing Claude hooks setup path
- `Copilot CLI` tab for Copilot hook install/remove status and action

The default selected tab may remain Claude Code to preserve the current primary
path. Users can switch to Copilot CLI during onboarding and install hooks there.
Each tab explains that hook changes affect new sessions and that Agent Light
stores only local status metadata.

## Hook Installation

Copilot hook installation is manual. Agent Light must not modify Copilot
configuration until the user clicks Install.

The installer should use the official Copilot CLI user-level hook configuration
shape. Prefer a dedicated user-level hook file such as:

```text
~/.copilot/hooks/agent-light.json
```

if that format cleanly supports all required events. Otherwise use the
user-level `~/.copilot/settings.json` hooks block. The implementation plan
should verify the exact current Copilot CLI format before coding.

Install and remove operations must identify Agent Light entries by the
`AgentCopilotHook` command. They must not remove user hooks, Claude Code hooks,
or unrelated Copilot hooks. Repeated install and remove operations should be
idempotent.

## Liveness And Merging

Copilot hook sessions are event signals. Like Claude hook sessions, liveness
should trust them until the source prunes stale files or session end removes the
file.

No transcript fallback is planned for Copilot CLI in this first version.
Collector merging should not require provider-specific precedence beyond normal
session id deduplication, because Copilot CLI has only one source.

## Notifications

Copilot CLI sessions participate in existing aggregate status and notification
behavior:

- `needsInput` and `failed` can trigger attention notifications when enabled.
- `completedAt` can trigger individual completion notifications when enabled.
- idle Copilot sessions count toward all-agents-idle behavior.

Provider display name should render as `Copilot CLI`.

## Privacy

Copilot support must preserve Agent Light's local-only model. The helper and
collector do not call a network service and do not send data to GitHub or any
model provider.

The helper should not persist prompts, tool inputs, tool outputs, model
responses, or full hook payloads. It should write only compact status metadata.

## Testing

Add focused tests for:

- Copilot hook event mapping for working, idle completion, needs input, failed,
  unknown active events, and no-op informational events.
- `AgentCopilotHook` behavior through mapper-level tests where possible, and
  lightweight executable smoke coverage if the project pattern supports it.
- `CopilotHookSource` reading valid files, skipping invalid files, pruning old
  orphan files, and producing `RawSession` with provider `copilot-cli`.
- `CopilotHookInstaller` install/remove/idempotency behavior and preservation of
  unrelated Copilot hook entries.
- Settings and onboarding smoke coverage for the new Agents container and agent
  tab selection.

Run `swift test`. Also run `swift build` or the existing bundle verification
script when packaging files change.

## Documentation

Update:

- `AGENTS.md` packaged executable list and important paths.
- `README.md` provider support text if applicable.
- A new `docs/copilot-cli-support.md` describing scope, setup, status mapping,
  privacy, and session restart guidance.
- Release packaging notes if needed.

Documentation must be explicit that this is Copilot CLI support, not general
VS Code Copilot support.

## Open Implementation Checks

Before coding, verify the current Copilot CLI hook configuration format and
event names against GitHub's official documentation. The design intentionally
keeps the installer isolated so any format differences affect only Copilot
files.

## Acceptance Criteria

- Agent Light can install and remove Copilot CLI hooks from Settings > Agents >
  Copilot CLI.
- Installed hooks invoke `AgentCopilotHook` and create compact local status
  files under `~/.agent-traffic-lights/copilot-hooks`.
- The collector surfaces active Copilot CLI sessions in the menu bar with
  provider `copilot-cli`.
- Working, idle, needs-input, failed, and completion notification behavior match
  the existing Claude hooks semantics where Copilot events provide equivalent
  signals.
- Claude Code hook installation, removal, and status detection continue to work
  without migration.
- The app bundle contains `AgentCopilotHook`.
- `swift test` passes.
