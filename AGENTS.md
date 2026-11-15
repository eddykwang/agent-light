# Agent Light Maintainer Notes

Agent Light is a SwiftPM macOS menu bar app that watches local coding-agent
activity and renders it as traffic lights in the menu bar.

## Product Shape

- App name: `Agent Light`
- Package name: `AgentTrafficLights`
- Minimum macOS: 14.0
- Main repo: `git@github.com:eddykwang/agent-light.git`
- Homebrew tap: `/Users/eddywang/Documents/homebrew-tap`
- Tap repo: `git@github.com:eddykwang/homebrew-tap.git`

The public install path is:

```bash
brew tap eddykwang/tap
brew install --cask agent-light
```

Releases v0.1.6 and v0.1.7 are Developer ID signed, notarized and stapled. Older releases
up to v0.1.5 remain ad-hoc signed and not notarized; see
`docs/signing-release-plan.md` for prerequisites and remaining validation.
Never commit or upload signing private keys, `.p12` / `.p8` files or credentials.

## Executables

This package builds five executables and one shared library:

- `AgentTrafficLights`: the menu bar app. Owns SwiftUI/AppKit UI, settings,
  notifications, onboarding, launch-at-login, update checks, and the status
  popover.
- `AgentStatusCollector`: background collector launched by the app. Reads local
  Codex, Claude Code, and Copilot CLI artifacts, classifies sessions, filters stale entries,
  and writes the shared status snapshot.
- `AgentCodexHook`: observation-only Codex lifecycle helper. Writes compact per-session metadata, never permission decisions.
- `AgentClaudeHook`: helper invoked by Claude Code hooks. It receives lifecycle
  JSON on stdin and writes compact per-session hook state.
- `AgentCopilotHook`: helper invoked by GitHub Copilot CLI hooks. It receives
  lifecycle JSON on stdin and writes compact per-session hook state.
- `AgentTrafficLightsCore`: shared Codable models and status writer.

The packaged app bundle must include all five executables:

```text
Agent Light.app/Contents/MacOS/AgentTrafficLights
Agent Light.app/Contents/MacOS/AgentStatusCollector
Agent Light.app/Contents/MacOS/AgentClaudeHook
Agent Light.app/Contents/MacOS/AgentCopilotHook
Agent Light.app/Contents/MacOS/AgentCodexHook
```

`script/package_release.sh` is the source of truth for bundle layout.

## Important Paths

Runtime status snapshot:

```text
~/.agent-traffic-lights/status.json
```

Claude Code hook metadata:

```text
~/.agent-traffic-lights/claude-hooks/*.json
```

Copilot CLI hook metadata and configuration:

```text
~/.agent-traffic-lights/copilot-hooks/*.json
~/.copilot/hooks/agent-light.json
```

Codex rollout files:

```text
~/.codex/sessions/**/rollout-*.jsonl
```

Claude Code transcript files:

```text
~/.claude/projects/**/*.jsonl
```

Claude Code settings modified by hook installation:

```text
~/.claude/settings.json
```

App preferences include:

```text
~/Library/Preferences/com.eddy.agent-light.plist
```

## Status Model

Statuses live in `Sources/AgentTrafficLightsCore/Models/AgentStatus.swift`:

- `failed`
- `needsInput`
- `working`
- `idle`
- `unknown`

Aggregate menu-bar priority is:

```text
failed / needsInput > working > idle > unknown
```

`AgentSession.completedAt` is an edge-triggered completion marker. Do not treat
it as a normal status. It exists so notifications can fire once per completed
turn without relying on a status debounce.
`AgentSession.usesCompletionMarker` marks event-backed sessions even before their
first completion, so interruption and disappearance do not imply completion.

## Collector Rules

The collector wiring is in:

```text
Sources/AgentStatusCollector/CollectorRunner.swift
Sources/AgentStatusCollector/main.swift
```

Sources:

- `CodexRolloutSource`: reads rollout JSONL; accepts known root sources and ChatGPT handoffs while rejecting Guardian/subagents.
- `CodexHookSource`: reads optional Codex hook state before rollout merging.
- `ClaudeCodeTranscriptSource`: reads Claude transcript JSONL.
- `ClaudeCodeHookSource`: reads Agent Light hook state.
- `CopilotHookSource`: reads Agent Light Copilot CLI hook state.

Liveness and stale-session behavior lives in:

```text
Sources/AgentStatusCollector/SessionLiveness.swift
```

Hook state is authoritative over transcript state for the same Claude Code
session. `CollectorRunner` gives hook entries a 60 second authority grace window
so a lagging transcript `idle` does not override hook `working`, `needsInput`,
or `failed`.

Do not reintroduce short "pending idle" debounces for Claude hooks. Claude Code
can emit multiple lifecycle events during long work, and completion
notifications should key off `completedAt`, not status wobble.

## Claude Code Hooks

Hook installation lives in:

```text
Sources/AgentTrafficLights/Services/ClaudeHookInstaller.swift
```

The installer adds Agent Light command hooks to Claude Code settings. It covers
events including session start, user prompt submit, tool use, permission/input
requests, stop, stop failure, subagent/task events, and session end.

Notification hooks are matcher-based:

- `idle_prompt`
- `permission_prompt`
- `elicitation_dialog`

`AgentClaudeHook` reads notification_type from current payloads; argv matcher is an older-version fallback. Child-scoped agent_id events cannot overwrite the main session; SubagentStart is a parent-side start signal.

Recent Claude Code versions reload hook settings. Older versions may require a restart. If the app bundle moves,
install hooks again so Claude Code points at the current bundled helper path.

## Codex Hooks

Optional Codex hooks are installed through Settings > Agents > Codex (also in onboarding).
Use Codex 0.169 or later; upgrade older CLIs sharing CODEX_HOME before installing.
The installer preserves other entries in CODEX_HOME/hooks.json. Exact hook definitions
must be reviewed and trusted in Codex Settings > Hooks or /hooks after installation/repair.
Never auto-trust hooks. Configured status does not prove trust or runtime support.
The helper outputs {} only; it never returns permission decisions or continuation fields.
Its state is ~/.agent-traffic-lights/codex-hooks/*.json, with millisecond numeric dates.
Stop advances completedAt once per turn; Interrupt/SessionEnd do not invent completion.
The collector reads it ahead of rollouts with the same session id and standard hook grace.
CODEX_HOME and CLAUDE_CONFIG_DIR must be inherited by Agent Light/collector as well as the CLI.

## Copilot CLI Hooks

Copilot hook installation lives in:

```text
Sources/AgentTrafficLights/Services/CopilotHookInstaller.swift
```

The installer owns only `~/.copilot/hooks/agent-light.json`. It deliberately
does not register `preToolUse`, whose command-hook failures can deny Copilot
tool execution, or `permissionRequest`, which fires before an actual prompt is
known to be necessary. Attention state comes from matcher-filtered
`notification` events. Terminal states remain visible for 60 seconds.

Copilot support covers the local CLI only. It does not read prompts, tool
payloads, transcripts, VS Code state, or cloud-agent state.

## App UI

Key UI files:

- `Sources/AgentTrafficLights/App/StatusBarController.swift`: menu bar icon,
  popover, responsive panel layout, menu rows, session actions, update banner.
- `Sources/AgentTrafficLights/UI/OnboardingView.swift`: first-run onboarding.
- `Sources/AgentTrafficLights/UI/OnboardingFlow.swift`: onboarding state
  machine.
- `Sources/AgentTrafficLights/UI/SettingsView.swift`: settings window.
- `Sources/AgentTrafficLights/UI/TrafficLightIconRenderer.swift`: status icon
  rendering.
- `Sources/AgentTrafficLights/Support/ProviderIconRenderer.swift`: provider icons.

Onboarding is controlled by `AppSettings.hasCompletedOnboarding`. First launch
should show onboarding by default.

When changing popover behavior, test while the popover is open. Status updates,
notifications, and session state should continue changing without requiring the
user to close and reopen the menu.

## Settings

Settings live in `Sources/AgentTrafficLights/Services/AppSettings.swift`.

User-facing modes:

- traffic-light orientation: `vertical` or `horizontal`
- Claude Code mode: `automatic` transcript mode or `hooks`
- completion notifications: `off`, `individual`, or `allAgentsIdle`
- attention notifications
- launch at login

Default Claude Code mode is transcript mode. Hooks are recommended for Claude
Code users but should remain optional.

## Update Checks

Update checking lives in:

```text
Sources/AgentTrafficLights/Services/UpdateChecker.swift
```

It checks:

```text
https://api.github.com/repos/eddykwang/agent-light/releases/latest
```

The current app version comes from `CFBundleShortVersionString`, which is set
by `script/package_release.sh`.

## Tests

Run all tests:

```bash
swift test
```

Useful test groups:

- `AgentTrafficLightsCoreTests`: shared models, hook event mapping, status file
  writer.
- `AgentStatusCollectorTests`: Codex/Claude classifiers, transcript reader,
  liveness, collector merging.
- `AgentTrafficLightsTests`: settings, onboarding, hook installer, notifier,
  status parser/store, icon renderer, update checker.

When changing hook events, update both:

```text
Tests/AgentTrafficLightsCoreTests/ClaudeHookEventMapperTests.swift
Tests/AgentTrafficLightsTests/ClaudeHookInstallerTests.swift
```

For Copilot CLI hook changes, update:

```text
Tests/AgentTrafficLightsCoreTests/CopilotHookEventMapperTests.swift
Tests/AgentStatusCollectorTests/CopilotHookSourceTests.swift
Tests/AgentTrafficLightsTests/CopilotHookInstallerTests.swift
```

When changing collector precedence or stale-session rules, update:

```text
Tests/AgentStatusCollectorTests/CollectorRunnerTests.swift
Tests/AgentStatusCollectorTests/LivenessTests.swift
Tests/AgentStatusCollectorTests/ClaudeCodeHookSourceTests.swift
Tests/AgentStatusCollectorTests/CopilotHookSourceTests.swift
```

## Local Build

Build:

```bash
swift build
```

Build and run the app bundle:

```bash
./script/build_and_run.sh run
```

Verify the app bundle launches:

```bash
./script/build_and_run.sh verify
```

The development app bundle is written to:

```text
dist/Agent Light.app
```

## Release Checklist

1. Confirm git identity:

```bash
git config user.name
git config user.email
```

Expected email:

```text
9157831+eddykwang@users.noreply.github.com
```

2. Run tests:

```bash
swift test
python3 -m unittest discover -s Tests/ReleaseScriptsTests -v
python3 -m unittest discover -s Tests/HookHelpersTests -v
```

3. Build a local release zip if you want to inspect it before tagging:

```bash
SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
APPLE_TEAM_ID="YOURTEAMID" NOTARY_PROFILE="agent-light-release" \
./script/package_release.sh v0.1.7
```

4. Commit release changes.

5. Create and push a new tag:

```bash
git tag v0.1.7
git push origin master
git push origin v0.1.7
```

Signing and notarization run locally using Keychain credentials; do not export
private keys or Apple credentials to GitHub. Pushing a new `v*` tag runs tests.
Upload the locally verified ZIP to a draft GitHub release, then manually run
`.github/workflows/release.yml` with that tag to independently verify its asset.
Only publish the draft after the workflow and local installation checks pass.
Missing local signing or notarization credentials must fail closed.

Do not reuse old tags for normal releases. Use a new tag for each public build.
Only force-push a tag when intentionally repairing an early broken release.

## Homebrew Tap Release

After the GitHub release asset exists, update:

```text
/Users/eddywang/Documents/homebrew-tap/Casks/agent-light.rb
```

Set:

```ruby
version "0.1.7"
sha256 "<release zip sha256>"
```

Calculate SHA256 from the release zip:

```bash
shasum -a 256 Agent-Light-v0.1.7-macOS.zip
```

Commit and push the tap:

```bash
cd /Users/eddywang/Documents/homebrew-tap
git add Casks/agent-light.rb
git commit -m "agent-light 0.1.7"
git push origin main
```

Local cask test from the tap repo:

```bash
brew install --cask ./Casks/agent-light.rb
```

Installed-user update path:

```bash
brew update
brew upgrade --cask agent-light
```

Homebrew may require trust for this tap:

```bash
brew trust eddykwang/tap
```

## Signing and First Launch

Release v0.1.6 and later must be Developer ID signed, notarized and stapled.
The cask URL is `Agent-Light-v#{version}-macOS.zip`. Keep the cask and README
consistent, and never disable quarantine to make installation checks pass.
Normal macOS download confirmations, notification permission and login-item
approval may still appear. Older release assets remain unsigned and unnotarized.
