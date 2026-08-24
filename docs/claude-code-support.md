# Claude Code Support

Agent Light supports Claude Code through two local modes:

1. **Default mode** reads Claude Code transcript files and combines them with
   local process checks.
2. **Hooks mode** asks Claude Code to send lifecycle status events to Agent
   Light's bundled helper for more precise permission, input, and completion
   detection.

The menu bar app still reads only Agent Light's shared status file. It does not
call Claude Code, does not call an LLM, and does not add anything to Claude
Code's model context.

## Default Mode

Default mode requires no Claude Code settings changes. When Agent Light
launches, `AppDelegate` starts the bundled `AgentStatusCollector` process. The
collector scans Claude Code transcript files under:

```text
~/.claude/projects/**/*.jsonl
```

It classifies recent transcript entries and writes the shared status file:

```text
~/.agent-traffic-lights/status.json
```

### Default Status Mapping

Claude Code transcripts expose turn progress well, but do not reliably expose
every permission or input prompt.

- recent user, assistant, tool-use, or attachment activity -> `working`
- assistant stop reason `tool_use` -> `working`
- assistant stop reason `end_turn` or `stop_sequence` -> `idle`
- last prompt marker -> `idle`
- unrecognized or empty transcript state -> `unknown`

Transcript-only mode intentionally avoids treating every tool error as a red
failure state. Claude Code can recover from many tool errors inside a normal
turn, so marking those as failed caused too many false alarms.

## Hooks Mode

Hooks mode is optional and can be enabled from **Settings... > Agents > Claude Code**. It
installs Agent Light command hooks into:

```text
~/.claude/settings.json
```

Each installed hook calls the bundled `AgentClaudeHook` helper inside the app
bundle. Claude Code sends lifecycle event JSON to the helper on standard input.
The helper maps that event to a compact local status file under:

```text
~/.agent-traffic-lights/claude-hooks
```

The collector reads those hook status files before transcript files, so hook
status wins when both sources describe the same Claude Code session.

Hooks mode improves detection for states that transcript mode cannot always see,
especially permission prompts, explicit input requests, stop events, and failed
stop events.

### Hook Privacy

Agent Light hooks are status hooks, not transcript readers.

- They do not send prompts to Agent Light.
- They do not send tool inputs to Agent Light.
- They do not send model responses to Agent Light.
- They do not call a network service.
- They write only local status metadata: session id, workspace path, transcript
  path, status, short detail, and update time.

## Liveness

Claude Code writes transcript files and closes them between writes, so `lsof`
open-file checks against the transcript itself are not reliable for Claude Code.
The collector treats recently modified Claude Code transcript files as live.

For stale `working` or `needsInput` sessions, the collector also checks whether
Claude Code processes still exist in the same workspace. If multiple stale
sessions exist in one workspace, only the most recently updated sessions up to
the live process count are kept. These process checks are read-only; the
collector never starts, stops, or signals Claude Code processes.

## Installing And Removing Hooks

Use **Settings... > Agents > Claude Code** for normal install and removal. Installing hooks
also switches Claude Code status mode to Hooks. Removing hooks switches it back
to Default.

Claude Code reads hook settings when a session starts. Restart existing Claude
Code sessions after installing or removing hooks.

If you move `Agent Light.app` after installing hooks, install hooks again so the
stored command points at the new app bundle path.

You can also remove Agent Light hook entries from the command line while
preserving the rest of your Claude Code settings:

```bash
./script/uninstall_claude_code_hooks.sh
```

Pass a custom settings path for testing or non-default setups:

```bash
./script/uninstall_claude_code_hooks.sh /path/to/settings.json
```
