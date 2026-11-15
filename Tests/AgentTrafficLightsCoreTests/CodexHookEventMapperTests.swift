import XCTest
import AgentTrafficLightsCore

final class CodexHookEventMapperTests: XCTestCase {
    private func event(_ name: String, turn: String = "turn-1") -> [String: Any] {
        ["session_id": "session-1", "cwd": "/tmp/demo", "hook_event_name": name, "turn_id": turn]
    }

    func testWorkingApprovalCompletionAndDuplicateStop() throws {
        let working = try XCTUnwrap(CodexHookEventMapper.state(from: event("UserPromptSubmit")))
        let attention = try XCTUnwrap(CodexHookEventMapper.state(from: event("PermissionRequest"), previous: working))
        XCTAssertEqual(attention.status, .needsInput)
        let resumed = try XCTUnwrap(CodexHookEventMapper.state(from: event("PostToolUse"), previous: attention))
        XCTAssertEqual(resumed.status, .working)
        let done = try XCTUnwrap(CodexHookEventMapper.state(from: event("Stop"), previous: resumed, now: Date(timeIntervalSince1970: 100)))
        XCTAssertEqual(done.status, .idle)
        XCTAssertEqual(done.completedAt, Date(timeIntervalSince1970: 100))
        let duplicate = CodexHookEventMapper.state(from: event("Stop"), previous: done, now: Date(timeIntervalSince1970: 200))
        XCTAssertEqual(duplicate?.completedAt, done.completedAt)
        XCTAssertNil(CodexHookEventMapper.state(from: event("PostToolUse"), previous: done))
    }

    func testNewTurnPreservesMarkerAndRejectsOldTurnEvents() throws {
        let done = try XCTUnwrap(CodexHookEventMapper.state(from: event("Stop"), now: Date(timeIntervalSince1970: 100)))
        let next = try XCTUnwrap(CodexHookEventMapper.state(from: event("UserPromptSubmit", turn: "turn-2"), previous: done))
        XCTAssertEqual(next.completedAt, done.completedAt)
        XCTAssertNil(CodexHookEventMapper.state(from: event("Stop"), previous: next))
        XCTAssertNil(CodexHookEventMapper.state(from: event("PermissionRequest"), previous: next))
        let complete = CodexHookEventMapper.state(from: event("Stop", turn: "turn-2"), previous: next, now: Date(timeIntervalSince1970: 100))
        XCTAssertGreaterThan(try XCTUnwrap(complete?.completedAt), try XCTUnwrap(done.completedAt))
    }

    func testInputToolWaitsWithoutTreatingModelRetryAsTerminalFailure() throws {
        var input = event("PreToolUse"); input["tool_name"] = "request_user_input"
        let waiting = try XCTUnwrap(CodexHookEventMapper.state(from: input))
        XCTAssertEqual(waiting.status, .needsInput)
        XCTAssertEqual(CodexHookEventMapper.state(from: event("PostToolUse"), previous: waiting)?.status, .working)
        var retry = event("PostModelRequest"); retry["status"] = "failed"
        XCTAssertNil(CodexHookEventMapper.state(from: retry))
    }

    func testInterruptAndSessionEndDoNotInventCompletion() throws {
        let working = try XCTUnwrap(CodexHookEventMapper.state(from: event("UserPromptSubmit")))
        let interrupted = try XCTUnwrap(CodexHookEventMapper.state(from: event("Interrupt"), previous: working))
        XCTAssertEqual(interrupted.status, .idle)
        XCTAssertNil(interrupted.completedAt)
        let ended = try XCTUnwrap(CodexHookEventMapper.state(from: event("SessionEnd"), previous: interrupted))
        XCTAssertNotNil(ended.endedAt)
        XCTAssertNil(ended.completedAt)
        XCTAssertNil(CodexHookEventMapper.state(from: event("SessionStart"), previous: ended)?.endedAt)
    }

    func testChildUnknownAndMalformedInputsAreIgnored() {
        var child = event("PostToolUse"); child["agent_id"] = "child"
        XCTAssertNil(CodexHookEventMapper.state(from: child))
        XCTAssertNil(CodexHookEventMapper.state(from: event("NewFutureEvent")))
        for key in ["session_id", "cwd", "turn_id", "hook_event_name"] {
            var invalid = event("Stop"); invalid.removeValue(forKey: key)
            XCTAssertNil(CodexHookEventMapper.state(from: invalid))
        }
    }

    func testCompactionStartDoesNotResetActiveStateAndPayloadIsNotStored() throws {
        let active = try XCTUnwrap(CodexHookEventMapper.state(from: event("PermissionRequest")))
        var compact = event("SessionStart"); compact["source"] = "compact"
        XCTAssertEqual(CodexHookEventMapper.state(from: compact, previous: active)?.status, .needsInput)
        var prompt = event("UserPromptSubmit"); prompt["prompt"] = "private-prompt-canary"; prompt["tool_input"] = "private-tool-canary"
        let state = try XCTUnwrap(CodexHookEventMapper.state(from: prompt))
        let data = try JSONEncoder().encode(state)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("canary"))
    }
}
