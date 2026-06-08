import XCTest
import AgentTrafficLightsCore
@testable import AgentStatusCollector

final class CodexClassifierTests: XCTestCase {
    func testLifecycleTailClassifiesAsIdle() {
        let objects: [[String: Any]] = [
            ["type": "session_meta", "payload": ["id": "abc", "cwd": "/tmp/proj", "thread_source": "user"]],
            ["type": "event_msg", "payload": ["type": "task_started", "turn_id": "t1"]],
            ["type": "event_msg", "payload": ["type": "agent_message", "message": "working"]],
            ["type": "event_msg", "payload": ["type": "task_complete", "turn_id": "t1"]]
        ]
        let (status, _) = StatusClassifier.classifyCodex(objects: objects)
        XCTAssertEqual(status, .idle)
    }

    func testEmptyReturnsUnknown() {
        let (status, _) = StatusClassifier.classifyCodex(objects: [])
        XCTAssertEqual(status, .unknown)
    }

    func testTaskStartedIsWorking() {
        let objects: [[String: Any]] = [
            ["type": "session_meta", "payload": ["id": "abc", "cwd": "/tmp/proj", "thread_source": "user"]],
            ["type": "event_msg", "payload": ["type": "task_started", "turn_id": "t1"]]
        ]
        let (status, _) = StatusClassifier.classifyCodex(objects: objects)
        XCTAssertEqual(status, .working)
    }

    func testTaskCompleteIsIdle() {
        let objects: [[String: Any]] = [
            ["type": "session_meta", "payload": ["id": "abc", "cwd": "/tmp/proj", "thread_source": "user"]],
            ["type": "event_msg", "payload": ["type": "task_started", "turn_id": "t1"]],
            ["type": "event_msg", "payload": ["type": "task_complete", "turn_id": "t1"]]
        ]
        let (status, _) = StatusClassifier.classifyCodex(objects: objects)
        XCTAssertEqual(status, .idle)
    }

    func testTurnAbortedIsIdle() {
        let objects: [[String: Any]] = [
            ["type": "session_meta", "payload": ["id": "abc", "cwd": "/tmp/proj", "thread_source": "user"]],
            ["type": "event_msg", "payload": ["type": "task_started", "turn_id": "t1"]],
            ["type": "event_msg", "payload": ["type": "turn_aborted", "reason": "interrupted"]]
        ]
        let (status, _) = StatusClassifier.classifyCodex(objects: objects)
        XCTAssertEqual(status, .idle)
    }

    func testNonLifecycleEventsDoNotChangeState() {
        // token_count and agent_message between task_started and task_complete
        let objects: [[String: Any]] = [
            ["type": "event_msg", "payload": ["type": "task_started"]],
            ["type": "event_msg", "payload": ["type": "agent_message", "text": "thinking"]],
            ["type": "event_msg", "payload": ["type": "token_count", "count": 100]]
        ]
        let (status, _) = StatusClassifier.classifyCodex(objects: objects)
        XCTAssertEqual(status, .working)
    }
}
