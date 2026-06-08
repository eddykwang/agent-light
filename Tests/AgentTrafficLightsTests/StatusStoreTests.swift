import AgentTrafficLightsCore
import XCTest
import Combine
@testable import AgentTrafficLights

@MainActor
final class StatusStoreTests: XCTestCase {
    private var cancellables: Set<AnyCancellable> = []

    override func tearDown() {
        cancellables.removeAll()
        super.tearDown()
    }

    func testMissingFileSetsUnknownState() {
        let store = StatusStore(parser: StatusParser())

        store.reload(from: "/tmp/agent-traffic-lights-missing-\(UUID().uuidString).json")

        XCTAssertEqual(store.aggregateStatus, .unknown)
        XCTAssertFalse(store.message.isEmpty)
    }

    func testValidFileLoadsSessions() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-traffic-lights-\(UUID().uuidString).json")

        try """
        {
          "version": 1,
          "updatedAt": "2026-06-06T10:42:00Z",
          "sessions": [
            { "id": "one", "provider": "codex", "projectName": "Project", "status": "working", "updatedAt": "2026-06-06T10:42:00Z" }
          ]
        }
        """.write(to: url, atomically: true, encoding: .utf8)

        let store = StatusStore(
            parser: StatusParser(),
            now: { ISO8601DateFormatter().date(from: "2026-06-06T10:43:00Z")! }
        )
        store.reload(from: url.path)

        XCTAssertEqual(store.aggregateStatus, .working)
        XCTAssertEqual(store.visibleSessions.count, 1)
    }

    func testStaleSnapshotSetsUnknownState() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-traffic-lights-stale-\(UUID().uuidString).json")

        try """
        {
          "version": 1,
          "updatedAt": "2026-06-06T10:00:00Z",
          "sessions": [
            { "id": "one", "provider": "codex", "projectName": "Project", "status": "working", "updatedAt": "2026-06-06T10:00:00Z" }
          ]
        }
        """.write(to: url, atomically: true, encoding: .utf8)

        let store = StatusStore(
            parser: StatusParser(),
            now: { Date(timeIntervalSince1970: 4_102_444_800) },
            staleAfter: 60
        )
        store.reload(from: url.path)

        XCTAssertEqual(store.aggregateStatus, .unknown)
        XCTAssertTrue(store.message.contains("stale"))
    }

    func testKeepsOldSessionsWhenFileIsFresh() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-traffic-lights-session-stale-\(UUID().uuidString).json")

        try """
        {
          "version": 1,
          "updatedAt": "2026-06-06T10:10:00Z",
          "sessions": [
            { "id": "old-red", "provider": "codex", "projectName": "Old", "status": "needsInput", "updatedAt": "2026-06-06T10:00:00Z" },
            { "id": "fresh-yellow", "provider": "codex", "projectName": "Fresh", "status": "working", "updatedAt": "2026-06-06T10:09:00Z" }
          ]
        }
        """.write(to: url, atomically: true, encoding: .utf8)

        let store = StatusStore(
            parser: StatusParser(),
            now: { ISO8601DateFormatter().date(from: "2026-06-06T10:10:00Z")! },
            staleAfter: 60 * 60 * 24 * 7
        )
        store.reload(from: url.path)

        XCTAssertEqual(store.aggregateStatus, .needsInput)
        XCTAssertEqual(store.visibleSessions.map(\.id), ["fresh-yellow", "old-red"])
        XCTAssertEqual(store.message, "2 agent sessions")
    }

    func testKeepsOldIdleSessionsWhenFileIsFresh() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-traffic-lights-idle-session-stale-\(UUID().uuidString).json")

        try """
        {
          "version": 1,
          "updatedAt": "2026-06-06T10:10:00Z",
          "sessions": [
            { "id": "old-idle", "provider": "codex", "projectName": "Old Idle", "status": "idle", "updatedAt": "2026-06-06T10:08:30Z" },
            { "id": "active-working", "provider": "codex", "projectName": "Active", "status": "working", "updatedAt": "2026-06-06T10:08:30Z" }
          ]
        }
        """.write(to: url, atomically: true, encoding: .utf8)

        let store = StatusStore(
            parser: StatusParser(),
            now: { ISO8601DateFormatter().date(from: "2026-06-06T10:10:00Z")! },
            staleAfter: 60 * 60 * 24 * 7
        )
        store.reload(from: url.path)

        XCTAssertEqual(store.aggregateStatus, .working)
        XCTAssertEqual(store.visibleSessions.map(\.id), ["old-idle", "active-working"])
        XCTAssertEqual(store.message, "2 agent sessions")
    }

    func testReloadSkipsUnchangedFilesWithoutPublishing() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-traffic-lights-unchanged-\(UUID().uuidString).json")

        try """
        {
          "version": 1,
          "updatedAt": "2026-06-06T10:42:00Z",
          "sessions": [
            { "id": "one", "provider": "codex", "projectName": "Project", "status": "working", "updatedAt": "2026-06-06T10:42:00Z" }
          ]
        }
        """.write(to: url, atomically: true, encoding: .utf8)

        let store = StatusStore(
            parser: StatusParser(),
            now: { ISO8601DateFormatter().date(from: "2026-06-06T10:43:00Z")! }
        )
        var emissions = 0
        store.$aggregateStatus
            .dropFirst()
            .sink { _ in emissions += 1 }
            .store(in: &cancellables)

        store.reload(from: url.path)
        store.reload(from: url.path)

        XCTAssertEqual(emissions, 1)
    }
}
