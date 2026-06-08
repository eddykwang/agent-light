import AgentTrafficLightsCore
import XCTest
@testable import AgentTrafficLights

final class StatusSnapshotTests: XCTestCase {
    func testAggregateUsesRedBeforeYellowBeforeGreen() {
        let sessions = [
            AgentSession(id: "idle", provider: "codex", projectName: "Idle", status: .idle, detail: nil, workspacePath: nil, threadURL: nil, updatedAt: nil),
            AgentSession(id: "working", provider: "codex", projectName: "Working", status: .working, detail: nil, workspacePath: nil, threadURL: nil, updatedAt: nil),
            AgentSession(id: "blocked", provider: "codex", projectName: "Blocked", status: .needsInput, detail: nil, workspacePath: nil, threadURL: nil, updatedAt: nil)
        ]

        let snapshot = StatusSnapshot(version: 1, updatedAt: nil, sessions: sessions)

        XCTAssertEqual(snapshot.aggregateStatus, .needsInput)
    }

    func testAggregateIsWorkingWhenNoRedStatusExists() {
        let sessions = [
            AgentSession(id: "idle", provider: "codex", projectName: "Idle", status: .idle, detail: nil, workspacePath: nil, threadURL: nil, updatedAt: nil),
            AgentSession(id: "working", provider: "codex", projectName: "Working", status: .working, detail: nil, workspacePath: nil, threadURL: nil, updatedAt: nil)
        ]

        let snapshot = StatusSnapshot(version: 1, updatedAt: nil, sessions: sessions)

        XCTAssertEqual(snapshot.aggregateStatus, .working)
    }

    func testAggregatePrefersFailedWhenFailedAndNeedsInputBothExist() {
        let sessions = [
            AgentSession(id: "blocked", provider: "codex", projectName: "Blocked", status: .needsInput, detail: nil, workspacePath: nil, threadURL: nil, updatedAt: nil),
            AgentSession(id: "failed", provider: "codex", projectName: "Failed", status: .failed, detail: nil, workspacePath: nil, threadURL: nil, updatedAt: nil)
        ]

        let snapshot = StatusSnapshot(version: 1, updatedAt: nil, sessions: sessions)

        XCTAssertEqual(snapshot.aggregateStatus, .failed)
    }

    func testAggregateIsIdleForIntentionallyEmptyValidSnapshot() {
        let snapshot = StatusSnapshot(version: 1, updatedAt: nil, sessions: [])

        XCTAssertEqual(snapshot.aggregateStatus, .idle)
    }

    func testVisibleSessionsAreLimitedToFive() {
        let sessions = (0..<8).map { index in
            AgentSession(id: "\(index)", provider: "codex", projectName: "Project \(index)", status: .idle, detail: nil, workspacePath: nil, threadURL: nil, updatedAt: Date(timeIntervalSince1970: TimeInterval(index)))
        }

        let snapshot = StatusSnapshot(version: 1, updatedAt: nil, sessions: sessions)

        XCTAssertEqual(snapshot.visibleSessions(limit: 5).map(\.id), ["7", "6", "5", "4", "3"])
    }

    func testUnknownStatusStringDecodesAsUnknown() throws {
        let json = """
        {
          "version": 1,
          "sessions": [
            {
              "id": "future",
              "provider": "codex",
              "projectName": "Future",
              "status": "pausedForReview"
            }
          ]
        }
        """

        let snapshot = try JSONDecoder().decode(StatusSnapshot.self, from: Data(json.utf8))

        XCTAssertEqual(snapshot.sessions.first?.status, .unknown)
    }
}
