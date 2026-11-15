# Codex Support

Agent Light detects Codex sessions automatically from local rollout files.
Hooks are optional and add permission/input and completion signals.

## Setup

Open Agent Light to start automatic rollout detection. To add permission/input
and completion signals, open **Settings → Agents → Codex** and choose
**Install Hooks**.

Use Codex 0.169 or later; upgrade older CLI versions sharing the same Codex home
before installing hooks. Then review and trust the exact definitions in
**Codex Settings → Hooks**, or `/hooks` in Codex CLI. Repeat the review after
repairing hooks or moving Agent Light. Agent Light never grants trust;
**configured** does not mean trusted or prove runtime support.

The installer merges Agent Light entries into `~/.codex/hooks.json`, preserving
other hooks and settings. Choose **Repair Hooks** if the app path or event set
has changed, or **Remove Hooks** to return to rollout-only detection. Invalid
configuration is not overwritten.

`CODEX_HOME` changes the sessions and hook configuration root. Agent Light must
inherit the variable as well as Codex; see [custom configuration directories](usage.md#custom-configuration-directories).

## Optional hooks

The bundled `AgentCodexHook` observes session start, prompt submission, tool use,
permission requests, completion, interruption, and session end. It writes compact
state under `~/.agent-traffic-lights/codex-hooks/`.

- Prompt submission and tool activity report `working`.
- Permission requests and supported input-request tools report `needsInput`.
- `Stop` reports `idle` and advances the completion marker once per turn.
- `Interrupt` and `SessionEnd` report `idle` without creating completion alerts.

Child-scoped events cannot overwrite the main session. Duplicate or late tool
events do not undo completion. Model-request retries are not treated as terminal
failures. Hook state takes priority over a lagging rollout for the same session;
clearly newer rollout data can recover when hooks stop updating.

The helper returns `{}` and never makes a permission decision or asks Codex to
continue. It stores status metadata, not prompts, tool arguments, or model
responses, and makes no network calls.

## Rollout detection

When the app launches, `AppDelegate` starts the collector. The collector scans
Codex rollout files under:

```text
~/.codex/sessions/**/rollout-*.jsonl
```

It classifies recent rollout events, confirms live Codex sessions by checking
open rollout file handles, and writes the shared status file:

```text
~/.agent-traffic-lights/status.json
```

The menu bar app reads that status file. Monitoring does not call Codex or a
model, or add anything to Codex context. The app's update checker separately
contacts GitHub for release information.

### Status mapping without hooks

Codex rollout files expose turn lifecycle events:

- latest lifecycle event `task_started` -> `working`
- latest lifecycle event `task_complete` -> `idle`
- latest lifecycle event `turn_aborted` -> `idle`
- no recognized lifecycle event -> `unknown`

The collector tracks user threads, ChatGPT handoffs, and known older CLI root
sessions, while filtering out Guardian and subagent rollouts.
Codex approval-waiting state is not reliably represented in rollout JSONL, so
the collector cannot reliably infer `needsInput` from rollouts alone.

## Liveness

Codex keeps live rollout files open while the app server owns the thread. The
collector uses `lsof` against each rollout path and keeps a session while the
file is open, with a short recency fallback for transient checks.
