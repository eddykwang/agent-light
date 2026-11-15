"""Run real helper executables with isolated metadata directories; never edit agent config."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


class HookHelperTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        override = os.environ.get("AGENT_LIGHT_TEST_BIN_DIR")
        cls.binaries = Path(override or subprocess.check_output(
            ["swift", "build", "--show-bin-path"], text=True).strip())

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.env = {**os.environ, "AGENT_LIGHT_CODEX_HOOKS_DIR": str(self.root / "codex"),
                    "AGENT_LIGHT_CLAUDE_HOOKS_DIR": str(self.root / "claude")}

    def run_hook(self, executable, event, **extra):
        payload = {"session_id": "main", "cwd": str(self.root), "hook_event_name": event,
                   "turn_id": "turn-1", **extra}
        return subprocess.run([str(self.binaries / executable)], input=json.dumps(payload),
                              text=True, capture_output=True, env=self.env, timeout=3, check=True)

    def codex_state(self):
        return json.loads((self.root / "codex/main.json").read_text())

    def test_codex_lifecycle_is_observation_only_and_preserves_completion(self):
        expected = [("UserPromptSubmit", "working"), ("PermissionRequest", "needsInput"),
                    ("PostToolUse", "working"), ("Stop", "idle")]
        for event, status in expected:
            result = self.run_hook("AgentCodexHook", event, prompt="private-prompt-canary",
                                   tool_input={"secret": "private-tool-canary"})
            self.assertEqual(json.loads(result.stdout), {})
            self.assertEqual(self.codex_state()["status"], status)
        done = self.codex_state()["completedAt"]
        self.run_hook("AgentCodexHook", "Stop")
        self.assertEqual(self.codex_state()["completedAt"], done)
        self.assertNotIn("canary", (self.root / "codex/main.json").read_text())
        self.run_hook("AgentCodexHook", "UserPromptSubmit", turn_id="turn-2")
        self.run_hook("AgentCodexHook", "Stop", turn_id="turn-2")
        self.assertGreaterEqual(self.codex_state()["completedAt"], done + 1000)

    def test_codex_children_late_events_and_malformed_input_do_not_change_state(self):
        self.run_hook("AgentCodexHook", "Stop")
        before = (self.root / "codex/main.json").read_bytes()
        self.run_hook("AgentCodexHook", "PostToolUse", agent_id="child")
        self.run_hook("AgentCodexHook", "PostToolUse")
        self.run_hook("AgentCodexHook", "FutureEvent")
        result = subprocess.run([str(self.binaries / "AgentCodexHook")], input="bad json",
                                text=True, capture_output=True, env=self.env, timeout=3, check=True)
        self.assertEqual(json.loads(result.stdout), {})
        self.assertEqual((self.root / "codex/main.json").read_bytes(), before)

    def test_unwritable_state_is_fail_open_for_permission_hook(self):
        blocked = self.root / "not-a-directory"
        blocked.write_text("occupied")
        self.env["AGENT_LIGHT_CODEX_HOOKS_DIR"] = str(blocked)
        result = self.run_hook("AgentCodexHook", "PermissionRequest")
        self.assertEqual(json.loads(result.stdout), {})
        self.assertEqual(blocked.read_text(), "occupied")

    def test_claude_child_tool_and_end_cannot_overwrite_or_delete_main_completion(self):
        self.run_hook("AgentClaudeHook", "Stop")
        file = self.root / "claude/main.json"
        before = file.read_bytes()
        for event in ["PostToolUse", "StopFailure", "SessionEnd"]:
            self.run_hook("AgentClaudeHook", event, agent_id="child", agent_type="Explore")
        self.assertEqual(file.read_bytes(), before)
        self.run_hook("AgentClaudeHook", "Notification", notification_type="permission_prompt")
        self.assertEqual(json.loads(file.read_text())["status"], "needsInput")
        self.run_hook("AgentClaudeHook", "SessionEnd")
        self.assertFalse(file.exists())
