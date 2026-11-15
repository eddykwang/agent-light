import XCTest
@testable import AgentTrafficLightsCore

final class ClaudeHookEventMapperTests: XCTestCase {
    func testSessionStartMapsToIdle() {
        let state = ClaudeHookEventMapper.state(
            from: [
                "session_id": "abc",
                "cwd": "/tmp/demo",
                "hook_event_name": "SessionStart"
            ],
            now: Date(timeIntervalSince1970: 100)
        )

        XCTAssertEqual(state?.status, .idle)
        XCTAssertEqual(state?.detail, "Claude Code session started")
    }

    func testUserPromptSubmitMapsToWorking() {
        let state = ClaudeHookEventMapper.state(
            from: [
                "session_id": "abc",
                "cwd": "/tmp/demo",
                "transcript_path": "/tmp/demo/abc.jsonl",
                "hook_event_name": "UserPromptSubmit"
            ],
            now: Date(timeIntervalSince1970: 100)
        )

        XCTAssertEqual(state?.sessionId, "abc")
        XCTAssertEqual(state?.workspacePath, "/tmp/demo")
        XCTAssertEqual(state?.transcriptPath, "/tmp/demo/abc.jsonl")
        XCTAssertEqual(state?.status, .working)
    }

    func testNotificationPermissionPromptViaArgumentMapsToNeedsInput() {
        // Real Claude Code path: notification type arrives as the matcher argument, not in the payload.
        let state = ClaudeHookEventMapper.state(
            from: [
                "session_id": "abc",
                "cwd": "/tmp/demo",
                "hook_event_name": "Notification"
            ],
            notificationType: "permission_prompt",
            now: Date(timeIntervalSince1970: 100)
        )

        XCTAssertEqual(state?.status, .needsInput)
        XCTAssertEqual(state?.detail, "Claude Code needs permission")
    }

    func testNotificationWithoutTypeIsNotNeedsInput() {
        // Regression guard: Claude Code does not put notification_type in the payload. A bare
        // Notification (no matcher arg) must not change state.
        let state = ClaudeHookEventMapper.state(
            from: [
                "session_id": "abc",
                "cwd": "/tmp/demo",
                "hook_event_name": "Notification"
            ],
            now: Date(timeIntervalSince1970: 100)
        )

        XCTAssertNil(state)
    }

    func testNotificationIdlePromptIsIdleNotNeedsInput() {
        // idle_prompt can fire after every response — it means "your turn", not "blocked".
        let state = ClaudeHookEventMapper.state(
            from: [
                "session_id": "abc",
                "cwd": "/tmp/demo",
                "hook_event_name": "Notification"
            ],
            notificationType: "idle_prompt",
            now: Date(timeIntervalSince1970: 100)
        )

        XCTAssertEqual(state?.status, .idle)
    }

    func testLocalCompletionEventsDoNotChangeMainSessionState() {
        for eventName in ["SubagentStop", "TaskCompleted", "TeammateIdle"] {
            let state = ClaudeHookEventMapper.state(
                from: [
                    "session_id": "abc",
                    "cwd": "/tmp/demo",
                    "hook_event_name": eventName
                ],
                now: Date(timeIntervalSince1970: 100)
            )

            XCTAssertNil(state, "\(eventName) should not mark the main session idle")
        }
    }

    func testNotificationElicitationDialogMapsToNeedsInput() {
        let state = ClaudeHookEventMapper.state(
            from: [
                "session_id": "abc",
                "cwd": "/tmp/demo",
                "hook_event_name": "Notification"
            ],
            notificationType: "elicitation_dialog",
            now: Date(timeIntervalSince1970: 100)
        )

        XCTAssertEqual(state?.status, .needsInput)
    }

    func testPermissionRequestMapsToNeedsInput() {
        let state = ClaudeHookEventMapper.state(
            from: [
                "session_id": "abc",
                "cwd": "/tmp/demo",
                "hook_event_name": "PermissionRequest"
            ],
            now: Date(timeIntervalSince1970: 100)
        )

        XCTAssertEqual(state?.status, .needsInput)
    }

    func testPermissionDeniedDoesNotChangeState() {
        // A denial means the user (or a deny rule) already responded, so it must NOT light the
        // attention lamp — the prior working/idle state stands until the next real event.
        let state = ClaudeHookEventMapper.state(
            from: [
                "session_id": "abc",
                "cwd": "/tmp/demo",
                "hook_event_name": "PermissionDenied"
            ],
            now: Date(timeIntervalSince1970: 100)
        )

        XCTAssertNil(state)
    }

    func testPostToolBatchMapsToWorking() {
        let state = ClaudeHookEventMapper.state(
            from: [
                "session_id": "abc",
                "cwd": "/tmp/demo",
                "hook_event_name": "PostToolBatch"
            ],
            now: Date(timeIntervalSince1970: 100)
        )

        XCTAssertEqual(state?.status, .working)
    }

    func testStopMapsToIdle() {
        let state = ClaudeHookEventMapper.state(
            from: [
                "session_id": "abc",
                "cwd": "/tmp/demo",
                "hook_event_name": "Stop"
            ],
            now: Date(timeIntervalSince1970: 100)
        )

        XCTAssertEqual(state?.status, .idle)
        XCTAssertEqual(state?.detail, "Last Claude Code turn completed")
        XCTAssertEqual(state?.completedAt, Date(timeIntervalSince1970: 100),
                       "Stop is the discrete turn-completion marker")
    }

    func testNonStopEventsDoNotSetCompletedAt() {
        for eventName in ["UserPromptSubmit", "PreToolUse", "PostToolUse", "SessionStart"] {
            let state = ClaudeHookEventMapper.state(
                from: [
                    "session_id": "abc",
                    "cwd": "/tmp/demo",
                    "hook_event_name": eventName
                ],
                now: Date(timeIntervalSince1970: 100)
            )
            XCTAssertNil(state?.completedAt, "\(eventName) must not stamp a completion marker")
        }
    }

    func testStopFailureMapsToFailed() {
        let state = ClaudeHookEventMapper.state(
            from: [
                "session_id": "abc",
                "cwd": "/tmp/demo",
                "hook_event_name": "StopFailure",
                "error": "hook_failed"
            ],
            now: Date(timeIntervalSince1970: 100)
        )

        XCTAssertEqual(state?.status, .failed)
        XCTAssertEqual(state?.detail, "Claude Code stop failed")
    }
    func testChildEventsDoNotOverwriteMainSessionButRootAgentTypeIsAllowed() {
        for name in ["PreToolUse", "PostToolUse", "PermissionRequest", "Stop", "StopFailure", "SessionEnd", "TaskCreated"] {
            let input: [String: Any] = ["session_id": "main", "cwd": "/tmp", "hook_event_name": name, "agent_id": "child", "agent_type": "Explore"]
            XCTAssertNil(ClaudeHookEventMapper.state(from: input), name)
        }
        XCTAssertEqual(ClaudeHookEventMapper.state(from: ["session_id": "main", "cwd": "/tmp", "hook_event_name": "SubagentStart", "agent_id": "child"])?.status, .working)
        XCTAssertEqual(ClaudeHookEventMapper.state(from: ["session_id": "main", "cwd": "/tmp", "hook_event_name": "UserPromptSubmit", "agent_type": "custom-main"])?.status, .working)
    }

    func testPayloadNotificationTypeTakesPrecedenceAndUnknownEventsDoNothing() {
        let input: [String: Any] = ["session_id": "main", "cwd": "/tmp", "hook_event_name": "Notification", "notification_type": "permission_prompt"]
        XCTAssertEqual(ClaudeHookEventMapper.state(from: input, notificationType: "idle_prompt")?.status, .needsInput)
        XCTAssertNil(ClaudeHookEventMapper.state(from: ["session_id": "main", "cwd": "/tmp", "hook_event_name": "FutureEvent"]))
    }

}
