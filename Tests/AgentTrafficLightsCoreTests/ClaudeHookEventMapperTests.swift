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
        // Notification (no matcher arg) must NOT light the red lamp.
        let state = ClaudeHookEventMapper.state(
            from: [
                "session_id": "abc",
                "cwd": "/tmp/demo",
                "hook_event_name": "Notification"
            ],
            now: Date(timeIntervalSince1970: 100)
        )

        XCTAssertNotEqual(state?.status, .needsInput)
        XCTAssertEqual(state?.status, .idle)
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

    func testPermissionDeniedMapsToNeedsInput() {
        let state = ClaudeHookEventMapper.state(
            from: [
                "session_id": "abc",
                "cwd": "/tmp/demo",
                "hook_event_name": "PermissionDenied"
            ],
            now: Date(timeIntervalSince1970: 100)
        )

        XCTAssertEqual(state?.status, .needsInput)
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
}
