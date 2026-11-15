import AgentTrafficLightsCore
import XCTest
@testable import AgentStatusCollector

final class CodexHookSourceTests: XCTestCase {
    func testReadsSignalWithRolloutIDAndCompletionMarker() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Date(timeIntervalSince1970: 1000)
        let state = CodexHookEventState(sessionId: "root", status: .needsInput, detail: "Codex needs permission",
            workspacePath: "/tmp/project", transcriptPath: nil, updatedAt: now, completedAt: now.addingTimeInterval(-20))
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .millisecondsSince1970
        try encoder.encode(state).write(to: root.appendingPathComponent("root.json"))
        let sessions = try CodexHookSource(eventsRoot: root.path, now: { now }).currentSessions()
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.id, "root")
        XCTAssertEqual(sessions.first?.provider, "codex")
        XCTAssertEqual(sessions.first?.status, .needsInput)
        XCTAssertEqual(sessions.first?.completedAt, state.completedAt)
        XCTAssertEqual(sessions.first?.isEventSignal, true)
    }

    func testMalformedOrphanAndExpiredTerminalSignalsAreRemovedOrIgnored() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Date(timeIntervalSince1970: 100000)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .millisecondsSince1970
        for (name, updated, ended) in [("orphan", now.addingTimeInterval(-90000), nil),
                                        ("expired", now.addingTimeInterval(-61), now.addingTimeInterval(-61)),
                                        ("recent", now.addingTimeInterval(-30), now.addingTimeInterval(-30))] {
            let state = CodexHookEventState(sessionId: name, status: .idle, detail: "ended", workspacePath: "/tmp",
                transcriptPath: nil, updatedAt: updated, endedAt: ended)
            try encoder.encode(state).write(to: root.appendingPathComponent("\(name).json"))
        }
        try Data("bad json".utf8).write(to: root.appendingPathComponent("bad.json"))
        XCTAssertEqual(try CodexHookSource(eventsRoot: root.path, now: { now }).currentSessions().map(\.id), ["recent"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("expired.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("orphan.json").path))
    }
}
