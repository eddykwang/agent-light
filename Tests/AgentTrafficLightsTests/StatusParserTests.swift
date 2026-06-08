import AgentTrafficLightsCore
import XCTest
@testable import AgentTrafficLights

final class StatusParserTests: XCTestCase {
    func testParsesValidSnapshot() throws {
        let json = """
        {
          "version": 1,
          "updatedAt": "2026-06-06T10:42:00Z",
          "sessions": [
            {
              "id": "session-1",
              "provider": "codex",
              "projectName": "Agent Light",
              "status": "working",
              "detail": "Running tests",
              "workspacePath": "/tmp/project",
              "threadUrl": "codex://threads/session-1",
              "updatedAt": "2026-06-06T10:42:00Z"
            }
          ]
        }
        """.data(using: .utf8)!

        let result = StatusParser().parse(data: json)

        guard case .success(let snapshot) = result else {
            return XCTFail("Expected success")
        }

        XCTAssertEqual(snapshot.version, 1)
        XCTAssertEqual(snapshot.sessions.count, 1)
        XCTAssertEqual(snapshot.sessions[0].status, .working)
        XCTAssertEqual(snapshot.aggregateStatus, .working)
    }

    func testDeduplicatesByNewestUpdatedAt() throws {
        let json = """
        {
          "version": 1,
          "updatedAt": "2026-06-06T10:42:00Z",
          "sessions": [
            { "id": "same", "provider": "codex", "projectName": "Old", "status": "idle", "updatedAt": "2026-06-06T10:40:00Z" },
            { "id": "same", "provider": "codex", "projectName": "New", "status": "needsInput", "updatedAt": "2026-06-06T10:42:00Z" }
          ]
        }
        """.data(using: .utf8)!

        let result = StatusParser().parse(data: json)

        guard case .success(let snapshot) = result else {
            return XCTFail("Expected success")
        }

        XCTAssertEqual(snapshot.sessions.count, 1)
        XCTAssertEqual(snapshot.sessions[0].projectName, "New")
        XCTAssertEqual(snapshot.aggregateStatus, .needsInput)
    }

    func testDeduplicatesWithDeterministicFirstSeenOrderAndNewestReplacement() throws {
        let json = """
        {
          "version": 1,
          "updatedAt": "2026-06-06T10:42:00Z",
          "sessions": [
            { "id": "a", "provider": "codex", "projectName": "A Old", "status": "idle", "updatedAt": "2026-06-06T10:40:00Z" },
            { "id": "b", "provider": "codex", "projectName": "B", "status": "working", "updatedAt": "2026-06-06T10:41:00Z" },
            { "id": "a", "provider": "codex", "projectName": "A New", "status": "needsInput", "updatedAt": "2026-06-06T10:42:00Z" }
          ]
        }
        """.data(using: .utf8)!

        let result = StatusParser().parse(data: json)

        guard case .success(let snapshot) = result else {
            return XCTFail("Expected success")
        }

        XCTAssertEqual(snapshot.sessions.map(\.id), ["a", "b"])
        XCTAssertEqual(snapshot.sessions[0].projectName, "A New")
        XCTAssertEqual(snapshot.sessions[1].projectName, "B")
    }

    func testDeduplicatesClaudeCodeSessionsByWorkspace() throws {
        let json = """
        {
          "version": 1,
          "updatedAt": "2026-06-06T10:43:00Z",
          "sessions": [
            { "id": "claude-code:old", "provider": "claude-code", "projectName": "Home", "workspacePath": "/tmp/agent-light-demo", "status": "idle", "updatedAt": "2026-06-06T10:40:00Z" },
            { "id": "claude-code:new", "provider": "claude-code", "projectName": "Home", "workspacePath": "/tmp/agent-light-demo", "status": "working", "updatedAt": "2026-06-06T10:43:00Z" },
            { "id": "codex-thread", "provider": "codex", "projectName": "Home", "workspacePath": "/tmp/agent-light-demo", "status": "idle", "updatedAt": "2026-06-06T10:41:00Z" }
          ]
        }
        """.data(using: .utf8)!

        let result = StatusParser().parse(data: json)

        guard case .success(let snapshot) = result else {
            return XCTFail("Expected success")
        }

        XCTAssertEqual(snapshot.sessions.map(\.id), ["claude-code:new", "codex-thread"])
        XCTAssertEqual(snapshot.aggregateStatus, .working)
    }

    func testInvalidJSONReturnsFailureMessage() {
        let result = StatusParser().parse(data: Data("{".utf8))

        guard case .failure(let message) = result else {
            return XCTFail("Expected failure")
        }

        XCTAssertFalse(message.localizedDescription.isEmpty)
    }

    func testInvalidJSONFailureProvidesLocalizedDescription() {
        let result = StatusParser().parse(data: Data("{".utf8))

        guard case .failure(let message) = result else {
            return XCTFail("Expected failure")
        }

        XCTAssertEqual(message.localizedDescription, message.message)
    }

    func testFixtureSnapshotsParseWithExpectedAggregateStatuses() throws {
        let cases: [(name: String, aggregateStatus: AgentStatus)] = [
            ("idle.json", .idle),
            ("working.json", .working),
            ("claude-code-working.json", .working),
            ("needs-input.json", .needsInput),
            ("failed.json", .failed)
        ]

        for testCase in cases {
            let result = StatusParser().parse(data: try fixtureData(named: testCase.name))

            guard case .success(let snapshot) = result else {
                return XCTFail("Expected \(testCase.name) to parse")
            }

            XCTAssertEqual(snapshot.aggregateStatus, testCase.aggregateStatus, testCase.name)
        }
    }

    func testInvalidFixtureReturnsFailure() throws {
        let result = StatusParser().parse(data: try fixtureData(named: "invalid.json"))

        guard case .failure(let message) = result else {
            return XCTFail("Expected failure")
        }

        XCTAssertFalse(message.localizedDescription.isEmpty)
    }

    private func fixtureData(named name: String) throws -> Data {
        let testFileURL = URL(fileURLWithPath: #filePath)
        var directory = testFileURL.deletingLastPathComponent()

        while directory.path != directory.deletingLastPathComponent().path {
            let fixtureURL = directory
                .appendingPathComponent("fixtures/status", isDirectory: true)
                .appendingPathComponent(name)

            if FileManager.default.fileExists(atPath: fixtureURL.path) {
                return try Data(contentsOf: fixtureURL)
            }

            directory.deleteLastPathComponent()
        }

        throw FixtureError.missing(name)
    }

    private enum FixtureError: Error {
        case missing(String)
    }
}
