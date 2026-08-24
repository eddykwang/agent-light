import AgentStatusCollector
import AgentTrafficLightsCore
import XCTest

final class CopilotHookSourceTests: XCTestCase {
    func testReadsCopilotHookState() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeState(
            CopilotHookEventState(
                sessionId: "abc",
                status: .needsInput,
                detail: "Copilot CLI needs input",
                workspacePath: "/tmp/demo",
                updatedAt: Date(timeIntervalSince1970: 900),
                completedAt: Date(timeIntervalSince1970: 800)
            ),
            to: root.appendingPathComponent("abc.json")
        )

        let sessions = try CopilotHookSource(
            eventsRoot: root.path,
            now: { Date(timeIntervalSince1970: 1_000) },
            pruneAfter: 200
        ).currentSessions()

        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.id, "copilot-cli:abc")
        XCTAssertEqual(sessions.first?.provider, "copilot-cli")
        XCTAssertEqual(sessions.first?.projectName, "demo")
        XCTAssertEqual(sessions.first?.status, .needsInput)
        XCTAssertEqual(sessions.first?.completedAt, Date(timeIntervalSince1970: 800))
        XCTAssertEqual(sessions.first?.isEventSignal, true)
    }

    func testRetainsTerminalStateForSixtySecondsThenPrunesIt() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("short.json")
        try writeState(
            CopilotHookEventState(
                sessionId: "short",
                status: .idle,
                detail: "done",
                workspacePath: "/tmp/demo",
                updatedAt: Date(timeIntervalSince1970: 900),
                completedAt: Date(timeIntervalSince1970: 900),
                endedAt: Date(timeIntervalSince1970: 950)
            ),
            to: file
        )

        let retained = try CopilotHookSource(
            eventsRoot: root.path,
            now: { Date(timeIntervalSince1970: 1_010) }
        ).currentSessions()
        XCTAssertEqual(retained.count, 1)

        let pruned = try CopilotHookSource(
            eventsRoot: root.path,
            now: { Date(timeIntervalSince1970: 1_011) }
        ).currentSessions()
        XCTAssertTrue(pruned.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testPrunesOldOrphanAndSkipsMalformedFiles() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let orphan = root.appendingPathComponent("old.json")
        try writeState(
            CopilotHookEventState(
                sessionId: "old",
                status: .working,
                detail: "working",
                workspacePath: "/tmp/demo",
                updatedAt: Date(timeIntervalSince1970: 100)
            ),
            to: orphan
        )
        try Data("not json".utf8).write(to: root.appendingPathComponent("bad.json"))

        let sessions = try CopilotHookSource(
            eventsRoot: root.path,
            now: { Date(timeIntervalSince1970: 1_000) },
            pruneAfter: 100
        ).currentSessions()

        XCTAssertTrue(sessions.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.path))
    }

    private func makeDirectory() throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func writeState(_ state: CopilotHookEventState, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(state).write(to: url)
    }
}
