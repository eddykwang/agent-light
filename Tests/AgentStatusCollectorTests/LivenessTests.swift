import XCTest
import AgentTrafficLightsCore
@testable import AgentStatusCollector

final class LivenessTests: XCTestCase {

    // MARK: - LsofLivenessFilter (injected checker)

    func testKeepsFileOpenSessionRegardlessOfAge() {
        // A session whose file is held open by a process should be kept even if old
        let session = makeSession(provider: "codex", fileURL: URL(fileURLWithPath: "/p/open.jsonl"),
                                  status: .needsInput, updatedAt: Date(timeIntervalSince1970: 0))
        let filter = LsofLivenessFilter(
            checker: StubChecker(openPaths: ["/p/open.jsonl"]),
            now: { Date(timeIntervalSince1970: 100_000) }, // 100_000s later
            ccStaleAfter: 300,
            fallbackStaleAfter: 300
        )
        XCTAssertEqual(filter.aliveSessions(from: [session]).count, 1)
    }

    func testDropsDeadFileSessionPastFallback() {
        // No process has the file open AND it's older than fallbackStaleAfter → drop
        let session = makeSession(provider: "codex", fileURL: URL(fileURLWithPath: "/p/dead.jsonl"),
                                  status: .working, updatedAt: Date(timeIntervalSince1970: 0))
        let filter = LsofLivenessFilter(
            checker: StubChecker(openPaths: []),
            now: { Date(timeIntervalSince1970: 10_000) },
            ccStaleAfter: 300,
            fallbackStaleAfter: 300
        )
        XCTAssertEqual(filter.aliveSessions(from: [session]).count, 0)
    }

    func testCCSessionAliveIfRecentMtime() {
        // CC sessions use mtime (not lsof) — recent file = alive
        let now = Date(timeIntervalSince1970: 1_000)
        let session = makeSession(provider: "claude-code",
                                  fileURL: URL(fileURLWithPath: "/p/cc.jsonl"),
                                  status: .idle,
                                  updatedAt: now.addingTimeInterval(-30)) // 30s ago
        let filter = LsofLivenessFilter(
            checker: StubChecker(openPaths: []), // lsof returns empty for CC
            now: { now },
            ccStaleAfter: 300,
            fallbackStaleAfter: 300
        )
        XCTAssertEqual(filter.aliveSessions(from: [session]).count, 1)
    }

    func testCCSessionDroppedIfStaleMtime() {
        // CC session with stale mtime and no open handle → dropped
        let now = Date(timeIntervalSince1970: 10_000)
        let session = makeSession(provider: "claude-code",
                                  fileURL: URL(fileURLWithPath: "/p/cc.jsonl"),
                                  status: .idle,
                                  updatedAt: now.addingTimeInterval(-400)) // 400s ago
        let filter = LsofLivenessFilter(
            checker: StubChecker(openPaths: []),
            now: { now },
            ccStaleAfter: 300,
            fallbackStaleAfter: 300
        )
        XCTAssertEqual(filter.aliveSessions(from: [session]).count, 0)
    }

    func testCCNeedsInputIsKeptWhenWorkspaceHasLiveProcess() {
        let now = Date(timeIntervalSince1970: 1_000)
        let session = makeSession(id: "cc-needs-input",
                                  provider: "claude-code",
                                  workspacePath: "/p",
                                  fileURL: URL(fileURLWithPath: "/p/hook.json"),
                                  status: .needsInput,
                                  updatedAt: now.addingTimeInterval(-900))
        let filter = LsofLivenessFilter(
            checker: StubChecker(openPaths: [], processCounts: ["/p": 1]),
            now: { now },
            ccActiveStaleAfter: 60,
            ccStaleAfter: 300,
            fallbackStaleAfter: 300
        )

        XCTAssertEqual(filter.aliveSessions(from: [session]).map(\.id), ["cc-needs-input"])
    }

    func testCCWorkingSessionUsesShorterActiveStaleWindow() {
        let now = Date(timeIntervalSince1970: 1_000)
        let session = makeSession(provider: "claude-code",
                                  fileURL: URL(fileURLWithPath: "/p/cc.jsonl"),
                                  status: .working,
                                  updatedAt: now.addingTimeInterval(-90))
        let filter = LsofLivenessFilter(
            checker: StubChecker(openPaths: []),
            now: { now },
            ccActiveStaleAfter: 60,
            ccStaleAfter: 300,
            fallbackStaleAfter: 300
        )
        XCTAssertEqual(filter.aliveSessions(from: [session]).count, 0)
    }

    func testCCWorkingSessionIsKeptWhenWorkspaceHasLiveProcess() {
        let now = Date(timeIntervalSince1970: 1_000)
        let session = makeSession(id: "cc1",
                                  provider: "claude-code",
                                  workspacePath: "/p",
                                  fileURL: URL(fileURLWithPath: "/p/cc.jsonl"),
                                  status: .working,
                                  updatedAt: now.addingTimeInterval(-600))
        let filter = LsofLivenessFilter(
            checker: StubChecker(openPaths: [], processCounts: ["/p": 1]),
            now: { now },
            ccActiveStaleAfter: 60,
            ccStaleAfter: 300,
            fallbackStaleAfter: 300
        )
        XCTAssertEqual(filter.aliveSessions(from: [session]).map(\.id), ["cc1"])
    }

    func testCCProcessCountKeepsOnlyMostRecentStaleWorkingSessionsInWorkspace() {
        let now = Date(timeIntervalSince1970: 1_000)
        let old = makeSession(id: "old",
                              provider: "claude-code",
                              workspacePath: "/p",
                              fileURL: URL(fileURLWithPath: "/p/old.jsonl"),
                              status: .working,
                              updatedAt: now.addingTimeInterval(-700))
        let recentStale = makeSession(id: "recent-stale",
                                      provider: "claude-code",
                                      workspacePath: "/p",
                                      fileURL: URL(fileURLWithPath: "/p/recent.jsonl"),
                                      status: .working,
                                      updatedAt: now.addingTimeInterval(-600))
        let filter = LsofLivenessFilter(
            checker: StubChecker(openPaths: [], processCounts: ["/p": 1]),
            now: { now },
            ccActiveStaleAfter: 60,
            ccStaleAfter: 300,
            fallbackStaleAfter: 300
        )

        XCTAssertEqual(filter.aliveSessions(from: [old, recentStale]).map(\.id), ["recent-stale"])
    }

    func testCCRecentWorkingConsumesWorkspaceProcessSlotBeforeStaleWorkingSessions() {
        let now = Date(timeIntervalSince1970: 1_000)
        let stale = makeSession(id: "stale",
                                provider: "claude-code",
                                workspacePath: "/p",
                                fileURL: URL(fileURLWithPath: "/p/stale.jsonl"),
                                status: .working,
                                updatedAt: now.addingTimeInterval(-600))
        let recent = makeSession(id: "recent",
                                 provider: "claude-code",
                                 workspacePath: "/p",
                                 fileURL: URL(fileURLWithPath: "/p/recent.jsonl"),
                                 status: .working,
                                 updatedAt: now.addingTimeInterval(-30))
        let filter = LsofLivenessFilter(
            checker: StubChecker(openPaths: [], processCounts: ["/p": 1]),
            now: { now },
            ccActiveStaleAfter: 60,
            ccStaleAfter: 300,
            fallbackStaleAfter: 300
        )

        XCTAssertEqual(filter.aliveSessions(from: [stale, recent]).map(\.id), ["recent"])
    }

    // MARK: - Helpers

    private func makeSession(provider: String, fileURL: URL, status: AgentStatus, updatedAt: Date) -> RawSession {
        makeSession(id: "s1", provider: provider, workspacePath: "/p", fileURL: fileURL, status: status, updatedAt: updatedAt)
    }

    private func makeSession(id: String, provider: String, workspacePath: String, fileURL: URL,
                             status: AgentStatus, updatedAt: Date) -> RawSession {
        RawSession(id: id, provider: provider, projectName: "p", workspacePath: workspacePath,
                   threadURL: nil, fileURL: fileURL, status: status, detail: "d", updatedAt: updatedAt)
    }
}

private struct StubChecker: ProcessChecker {
    let openPaths: Set<String>
    var processCounts: [String: Int] = [:]

    func isFileOpen(path: String) -> Bool { openPaths.contains(path) }
    func claudeCodeProcessCount(workspacePath: String) -> Int { processCounts[workspacePath] ?? 0 }
}
