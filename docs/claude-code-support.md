# Claude Code Support

Agent Light supports Claude Code through two local modes:

1. **Default mode** reads Claude Code transcript files and combines them with
   local process checks.
2. **Hooks mode** asks Claude Code to send lifecycle status events to Agent
   Light's bundled helper for more precise permission, input, and completion
   detection.

The menu bar app still reads only Agent Light's shared status file. It does not
call Claude Code, does not call an LLM, and does not add anything to Claude
Code's model context. Update checks separately contact GitHub for release information.

`CLAUDE_CONFIG_DIR` changes the transcript/settings root. Agent Light must inherit
it as well as Claude Code; see [custom configuration directories](usage.md#custom-configuration-directories).

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
status takes priority over a lagging transcript for the same Claude Code session.
Clearly newer transcript data can recover when hooks stop updating. Child-scoped
events cannot replace or delete the main session's hook state.

Hooks mode improves detection for states that transcript mode cannot always see,
especially permission prompts, explicit input requests, stop events, and failed
stop events.

### Hook Privacy

Claude Code passes lifecycle event JSON to the helper. The helper extracts and
stores only local status metadata: session id, workspace path, transcript path,
status, short detail, and timestamps, including the completion marker. It does
not store prompts, tool inputs, model responses, or transcript contents, and
does not call a network service.

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

Recent Claude Code versions reload hook settings during a session. Older versions
may require a restart; start a new session if installation or removal is not picked up.

If you move `Agent Light.app` or the installed event set is incomplete, Settings
shows **Hooks need reinstalling**. Install again to repair Agent Light's entries
at the current app path while preserving other hooks and settings. Invalid
configuration is not overwritten.

You can also remove Agent Light hook entries from the command line while
preserving the rest of your Claude Code settings:

```bash
./script/uninstall_claude_code_hooks.sh
```

Pass a custom settings path for testing or non-default setups:

```bash
./script/uninstall_claude_code_hooks.sh /path/to/settings.json
```
