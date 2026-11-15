import XCTest
import AgentTrafficLightsCore
@testable import AgentStatusCollector

final class SessionSourceTests: XCTestCase {
    func testEventCompletionModeSurvivesSnapshotEncodingBeforeFirstCompletion() throws {
        let raw = RawSession(id: "hook", provider: "codex", projectName: "p", workspacePath: "/tmp/p",
                             threadURL: nil, fileURL: URL(fileURLWithPath: "/tmp/state.json"),
                             status: .idle, detail: "Interrupted", updatedAt: Date(), isEventSignal: true)
        let session = raw.toAgentSession().withCompletedAt(nil)
        let decoded = try JSONDecoder().decode(AgentSession.self, from: JSONEncoder().encode(session))
        XCTAssertEqual(decoded.usesCompletionMarker, true)
        XCTAssertNil(decoded.completedAt)
        let legacy = try JSONDecoder().decode(AgentSession.self, from: Data(#"{"id":"old","provider":"codex","projectName":"p","status":"idle"}"#.utf8))
        XCTAssertNil(legacy.usesCompletionMarker)
    }

    func testStubSourceReturnsSessions() throws {
        let stub = StubSource(sessions: [
            RawSession(id: "x", provider: "codex", projectName: "p", workspacePath: "/tmp/p",
                       threadURL: nil, fileURL: URL(fileURLWithPath: "/tmp/p.jsonl"), status: .working, detail: "d",
                       updatedAt: Date(timeIntervalSince1970: 10))
        ])
        let result = try stub.currentSessions()
        XCTAssertEqual(result.first?.id, "x")
    }
}

private struct StubSource: SessionSource {
    let sessions: [RawSession]
    func currentSessions() throws -> [RawSession] { sessions }
}
