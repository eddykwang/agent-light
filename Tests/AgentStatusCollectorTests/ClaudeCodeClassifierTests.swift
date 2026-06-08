import XCTest
import AgentTrafficLightsCore
@testable import AgentStatusCollector

final class ClaudeCodeClassifierTests: XCTestCase {
    func testToolUseTranscriptTailClassifiesAsWorking() {
        let objects: [[String: Any]] = [
            ["type": "assistant", "sessionId": "abc", "cwd": "/tmp/proj",
             "message": ["role": "assistant", "stop_reason": "tool_use",
                         "content": [["type": "tool_use", "name": "Bash"]]]]
        ]
        let (status, _) = StatusClassifier.classifyClaudeCode(objects: objects)
        XCTAssertEqual(status, .working)
    }

    func testStopSequenceTranscriptTailClassifiesAsIdle() {
        let objects: [[String: Any]] = [
            ["type": "assistant", "sessionId": "abc", "cwd": "/tmp/proj",
             "message": ["role": "assistant", "stop_reason": "stop_sequence",
                         "content": [["type": "text", "text": "Done"]]]]
        ]
        let (status, _) = StatusClassifier.classifyClaudeCode(objects: objects)
        XCTAssertEqual(status, .idle)
    }

    func testEmptyReturnsUnknown() {
        let (status, _) = StatusClassifier.classifyClaudeCode(objects: [])
        XCTAssertEqual(status, .unknown)
    }

    func testToolUseStopReasonIsWorking() {
        let objects: [[String: Any]] = [
            ["type": "assistant", "sessionId": "abc", "cwd": "/tmp",
             "message": ["role": "assistant", "stop_reason": "tool_use",
                         "content": [["type": "tool_use", "name": "Bash"]]]]
        ]
        let (status, _) = StatusClassifier.classifyClaudeCode(objects: objects)
        XCTAssertEqual(status, .working)
    }

    func testEndTurnStopReasonIsIdle() {
        let objects: [[String: Any]] = [
            ["type": "assistant", "sessionId": "abc", "cwd": "/tmp",
             "message": ["role": "assistant", "stop_reason": "end_turn",
                         "content": [["type": "text", "text": "Done"]]]]
        ]
        let (status, _) = StatusClassifier.classifyClaudeCode(objects: objects)
        XCTAssertEqual(status, .idle)
    }

    func testStopSequenceIsIdle() {
        let objects: [[String: Any]] = [
            ["type": "assistant", "sessionId": "abc", "cwd": "/tmp",
             "message": ["role": "assistant", "stop_reason": "stop_sequence",
                         "content": [["type": "text", "text": "Done"]]]]
        ]
        let (status, _) = StatusClassifier.classifyClaudeCode(objects: objects)
        XCTAssertEqual(status, .idle)
    }

    func testRecoveredToolErrorDoesNotClassifyAsFailed() {
        let objects: [[String: Any]] = [
            ["type": "assistant", "sessionId": "abc", "cwd": "/tmp",
             "message": ["role": "assistant", "stop_reason": "tool_use",
                         "content": [["type": "tool_use", "name": "Bash"]]]],
            ["type": "user", "sessionId": "abc", "cwd": "/tmp",
             "message": ["role": "user", "content": [
                ["type": "tool_result", "is_error": true, "content": "command not found"]
             ]]],
            ["type": "assistant", "sessionId": "abc", "cwd": "/tmp",
             "message": ["role": "assistant", "stop_reason": "end_turn",
                         "content": [["type": "text", "text": "Handled it"]]]]
        ]
        let (status, _) = StatusClassifier.classifyClaudeCode(objects: objects)
        XCTAssertEqual(status, .idle)
    }

    func testLastEntryUserMeansWorking() {
        let objects: [[String: Any]] = [
            ["type": "assistant", "sessionId": "abc", "cwd": "/tmp",
             "message": ["role": "assistant", "stop_reason": "end_turn",
                         "content": [["type": "text", "text": "Done"]]]],
            ["type": "user", "sessionId": "abc", "cwd": "/tmp",
             "message": ["role": "user", "content": [["type": "text", "text": "Follow-up"]]]]
        ]
        let (status, _) = StatusClassifier.classifyClaudeCode(objects: objects)
        XCTAssertEqual(status, .working)
    }

    func testLastPromptEntryIsIdle() {
        let objects: [[String: Any]] = [
            ["type": "assistant", "sessionId": "abc", "cwd": "/tmp",
             "message": ["role": "assistant", "stop_reason": "stop_sequence",
                         "content": [["type": "text", "text": "Done"]]]],
            ["type": "last-prompt"]
        ]
        // last-prompt is not user/attachment so doesn't trigger working; last assistant is stop_sequence → idle
        let (status, _) = StatusClassifier.classifyClaudeCode(objects: objects)
        XCTAssertEqual(status, .idle)
    }

    func testLastPromptFollowedByMetadataIsIdle() {
        let objects: [[String: Any]] = [
            ["type": "assistant", "sessionId": "abc", "cwd": "/tmp",
             "message": ["role": "assistant", "stop_reason": "tool_use",
                         "content": [["type": "tool_use", "name": "Agent"]]]],
            ["type": "last-prompt", "sessionId": "abc"],
            ["type": "permission-mode", "permissionMode": "default", "sessionId": "abc"]
        ]
        let (status, _) = StatusClassifier.classifyClaudeCode(objects: objects)
        XCTAssertEqual(status, .idle)
    }

    func testEndTurnFollowedByHookAttachmentIsIdle() {
        let objects: [[String: Any]] = [
            ["type": "assistant", "sessionId": "abc", "cwd": "/tmp",
             "message": ["role": "assistant", "stop_reason": "end_turn",
                         "content": [["type": "text", "text": "Done"]]]],
            ["type": "attachment", "sessionId": "abc",
             "attachment": ["type": "hook_success", "hookName": "Stop"]]
        ]
        let (status, _) = StatusClassifier.classifyClaudeCode(objects: objects)
        XCTAssertEqual(status, .idle)
    }

    func testLastPromptOnlyWithNoAssistantIsIdle() {
        // New session that only has a last-prompt entry and no assistant yet
        let objects: [[String: Any]] = [["type": "last-prompt"]]
        let (status, _) = StatusClassifier.classifyClaudeCode(objects: objects)
        XCTAssertEqual(status, .idle)
    }
}
