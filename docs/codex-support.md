# Codex Support

Agent Light observes Codex automatically through the bundled
`AgentStatusCollector` process. No Codex hook installation is required.

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

The menu bar app still reads only that status file. It does not call Codex, does
not call a model, and does not add anything to Codex context.

## Status Mapping

Codex rollout files expose turn lifecycle events:

- latest lifecycle event `task_started` -> `working`
- latest lifecycle event `task_complete` -> `idle`
- latest lifecycle event `turn_aborted` -> `idle`
- no recognized lifecycle event -> `unknown`

The collector filters out guardian/subagent rollouts and tracks user threads.
Codex approval-waiting state is not reliably represented in rollout JSONL, so
the collector does not infer `needsInput` from Codex rollouts.

## Liveness

Codex keeps live rollout files open while the app server owns the thread. The
collector uses `lsof` against each rollout path and keeps a session while the
file is open, with a short recency fallback for transient checks.
