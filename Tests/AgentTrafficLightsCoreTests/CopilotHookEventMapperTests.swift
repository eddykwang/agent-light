import AgentTrafficLightsCore
import XCTest

final class CopilotHookEventMapperTests: XCTestCase {
    func testSessionStartWithoutPromptIsIdle() {
        let state = map("sessionStart")

        XCTAssertEqual(state?.status, .idle)
        XCTAssertEqual(state?.detail, "Copilot CLI session started")
        XCTAssertNil(state?.completedAt)
        XCTAssertNil(state?.endedAt)
    }

    func testSessionStartWithInitialPromptIsWorking() {
        let state = map("sessionStart", extra: ["initialPrompt": "build it"])

        XCTAssertEqual(state?.status, .working)
    }

    func testPromptAndToolEventsAreWorking() {
        for event in ["userPromptSubmitted", "postToolUse", "postToolUseFailure"] {
            XCTAssertEqual(map(event)?.status, .working, event)
        }
    }

    func testOnlyAttentionNotificationsMapToNeedsInput() {
        XCTAssertEqual(
            map("notification", extra: ["notification_type": "permission_prompt"])?.status,
            .needsInput
        )
        XCTAssertEqual(
            map("notification", extra: ["notification_type": "elicitation_dialog"])?.detail,
            "Copilot CLI needs input"
        )
        XCTAssertNil(map("notification", extra: ["notification_type": "agent_idle"]))
    }

    func testAgentStopSetsCompletionAndLaterWorkingEventPreservesIt() {
        let working = map("userPromptSubmitted", timestamp: 1_000)
        let stopped = map("agentStop", timestamp: 2_000, previous: working)
        let resumed = map("postToolUse", timestamp: 3_000, previous: stopped)

        XCTAssertEqual(stopped?.status, .idle)
        XCTAssertEqual(stopped?.completedAt, Date(timeIntervalSince1970: 2))
        XCTAssertEqual(resumed?.status, .working)
        XCTAssertEqual(resumed?.completedAt, stopped?.completedAt)
    }

    func testLateAsynchronousEventDoesNotOverwriteNewerState() {
        let stopped = map("agentStop", timestamp: 5_000)
        let lateNotification = map(
            "notification",
            timestamp: 4_000,
            extra: ["notification_type": "permission_prompt"],
            previous: stopped
        )

        XCTAssertNil(lateNotification)
    }

    func testOnlyExplicitUnrecoverableErrorFails() {
        XCTAssertNil(map("errorOccurred", extra: ["recoverable": true]))
        XCTAssertNil(map("errorOccurred"))
        XCTAssertEqual(map("errorOccurred", extra: ["recoverable": false])?.status, .failed)
    }

    func testSessionEndReasonsBecomeTerminalStates() {
        let complete = map("sessionEnd", timestamp: 2_000, extra: ["reason": "complete"])
        let userExit = map("sessionEnd", timestamp: 3_000, extra: ["reason": "user_exit"])
        let error = map("sessionEnd", timestamp: 4_000, extra: ["reason": "error"])
        let timeout = map("sessionEnd", timestamp: 5_000, extra: ["reason": "timeout"])

        XCTAssertEqual(complete?.status, .idle)
        XCTAssertEqual(complete?.completedAt, Date(timeIntervalSince1970: 2))
        XCTAssertEqual(complete?.endedAt, Date(timeIntervalSince1970: 2))
        XCTAssertEqual(userExit?.status, .idle)
        XCTAssertNil(userExit?.completedAt)
        XCTAssertEqual(error?.status, .failed)
        XCTAssertEqual(timeout?.status, .failed)
    }

    func testUsesPreviousWorkspaceWhenTerminalPayloadOmitsCwd() {
        let previous = map("userPromptSubmitted")
        let state = CopilotHookEventMapper.state(
            from: ["sessionId": "s1", "timestamp": 2_000, "reason": "user_exit"],
            eventName: "sessionEnd",
            previous: previous
        )

        XCTAssertEqual(state?.workspacePath, "/tmp/project")
    }

    func testRejectsUnknownOrIncompleteEvents() {
        XCTAssertNil(map("somethingNew"))
        XCTAssertNil(CopilotHookEventMapper.state(from: ["cwd": "/tmp"], eventName: "agentStop"))
    }

    private func map(
        _ event: String,
        timestamp: Double = 1_000,
        extra: [String: Any] = [:],
        previous: CopilotHookEventState? = nil
    ) -> CopilotHookEventState? {
        var input: [String: Any] = [
            "sessionId": "s1",
            "cwd": "/tmp/project",
            "timestamp": timestamp
        ]
        input.merge(extra, uniquingKeysWith: { _, new in new })
        return CopilotHookEventMapper.state(
            from: input,
            eventName: event,
            previous: previous,
            now: Date(timeIntervalSince1970: 99)
        )
    }
}
