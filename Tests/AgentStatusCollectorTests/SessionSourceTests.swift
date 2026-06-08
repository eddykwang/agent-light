import XCTest
import AgentTrafficLightsCore
@testable import AgentStatusCollector

final class SessionSourceTests: XCTestCase {
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
