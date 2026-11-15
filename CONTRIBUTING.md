# Contributing

Report bugs and propose features in [Issues](https://github.com/eddykwang/agent-light/issues).
Check existing issues first. For a bug, include the macOS and app versions, agent
and agent version, detection mode, reproduction steps, and expected behavior.
Use a small, redacted example rather than a full private transcript.

## Development

You need macOS 14 or later, Swift 5.10 or later, Xcode Command Line Tools, and
Python 3 for the helper and release-script tests.

```bash
git clone https://github.com/eddykwang/agent-light.git
cd agent-light
./script/build_and_run.sh run
```

The script builds `dist/Agent Light.app` and launches it. It stops an existing
Agent Light app and collector before starting the development build.

Build without launching:

```bash
swift build
```

## Tests

Run from the repository root:

```bash
swift test
python3 -m unittest discover -s Tests/ReleaseScriptsTests -v
python3 -m unittest discover -s Tests/HookHelpersTests -v
```

Run `swift build` before the helper-process tests if you have not already built
the executable targets. Those tests use temporary metadata directories.

## Pull requests

Keep each PR focused on one change. Explain the problem, the resulting behavior,
and how you checked it. Add regression coverage for changes to event mapping,
hook configuration, source precedence, or session liveness. For UI changes,
include a screenshot and check updates while the status panel stays open.

Provider behavior is documented in the [Codex](docs/codex-support.md),
[Claude Code](docs/claude-code-support.md), and [Copilot CLI](docs/copilot-cli-support.md)
guides. Update the relevant guide when behavior or setup changes.

Maintainers: see the [signing and release checklist](docs/signing-release-plan.md).
Signing private keys and Apple credentials stay in the local Keychain; never
include them in commits or release assets.
