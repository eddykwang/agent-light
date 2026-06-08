import AgentTrafficLightsCore
import XCTest
@testable import AgentTrafficLights

final class OpenCodexActionTests: XCTestCase {
    func testThreadURLWinsOverWorkspacePath() {
        let threadURL = URL(string: "codex://threads/session-1")!
        let session = makeSession(threadURL: threadURL, workspacePath: "/tmp/project")

        XCTAssertEqual(OpenCodexAction().urlToOpen(for: session), threadURL)
    }

    func testClaudeCodeOpensWorkspaceBeforeTranscript() {
        let transcriptURL = URL(string: "file:///tmp/transcript.jsonl")!
        let workspacePath = FileManager.default.temporaryDirectory.path
        let session = makeSession(provider: "claude-code", threadURL: transcriptURL, workspacePath: workspacePath)

        XCTAssertEqual(OpenCodexAction().urlToOpen(for: session), URL(fileURLWithPath: workspacePath))
    }

    func testWorkspacePathFallbackWhenNoThreadURL() {
        let workspacePath = FileManager.default.temporaryDirectory.path
        let session = makeSession(workspacePath: workspacePath)

        XCTAssertEqual(OpenCodexAction().urlToOpen(for: session), URL(fileURLWithPath: workspacePath))
    }

    func testURLToOpenIsNilWhenSessionHasNoOpenTarget() {
        let session = makeSession()

        XCTAssertNil(OpenCodexAction().urlToOpen(for: session))
        XCTAssertFalse(OpenCodexAction().canOpen(session))
    }

    func testInjectedOpenerReceivesExpectedURL() {
        let expectedURL = URL(string: "codex://threads/session-1")!
        let session = makeSession(threadURL: expectedURL)
        var openedURL: URL?
        let action = OpenCodexAction(openURL: { openedURL = $0 })

        action.open(session)

        XCTAssertEqual(openedURL, expectedURL)
    }

    func testRejectsExecutableFileURL() {
        let session = makeSession(
            threadURL: URL(string: "file:///tmp/evil.command"),
            workspacePath: nil
        )

        XCTAssertNil(OpenCodexAction().urlToOpen(for: session))
    }

    func testAllowsCodexScheme() {
        let session = makeSession(threadURL: URL(string: "codex://threads/abc"))

        XCTAssertEqual(OpenCodexAction().urlToOpen(for: session)?.scheme, "codex")
    }

    func testAllowsExistingDirectoryWorkspace() {
        let session = makeSession(
            provider: "claude-code",
            workspacePath: FileManager.default.temporaryDirectory.path
        )

        XCTAssertEqual(OpenCodexAction().urlToOpen(for: session)?.path.hasPrefix("/"), true)
    }

    private func makeSession(
        provider: String = "codex",
        threadURL: URL? = nil,
        workspacePath: String? = nil
    ) -> AgentSession {
        AgentSession(
            id: "session-1",
            provider: provider,
            projectName: "Project",
            status: .working,
            detail: nil,
            workspacePath: workspacePath,
            threadURL: threadURL,
            updatedAt: nil
        )
    }
}
