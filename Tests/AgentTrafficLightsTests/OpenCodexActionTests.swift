import AgentTrafficLightsCore
import XCTest
@testable import AgentTrafficLights

final class OpenCodexActionTests: XCTestCase {
    func testThreadURLIsPrimaryWhenCodexHandlerExists() {
        let threadURL = URL(string: "codex://threads/session-1")!
        let session = makeSession(threadURL: threadURL, workspacePath: "/tmp/project")
        let action = OpenCodexAction(canOpenApplication: { _ in true })

        XCTAssertEqual(action.threadURLToOpen(for: session), threadURL)
    }

    func testThreadURLIsUnavailableWhenCodexHandlerIsMissing() {
        let threadURL = URL(string: "codex://threads/session-1")!
        let session = makeSession(threadURL: threadURL, workspacePath: "/tmp/project")
        let action = OpenCodexAction(canOpenApplication: { _ in false })

        XCTAssertNil(action.threadURLToOpen(for: session))
    }

    func testClaudeCodeTranscriptIsNotAThreadURL() {
        let transcriptURL = URL(string: "file:///tmp/transcript.jsonl")!
        let workspacePath = FileManager.default.temporaryDirectory.path
        let session = makeSession(provider: "claude-code", threadURL: transcriptURL, workspacePath: workspacePath)

        XCTAssertNil(OpenCodexAction(canOpenApplication: { _ in true }).threadURLToOpen(for: session))
    }

    func testFolderURLUsesValidWorkspacePath() {
        let workspacePath = FileManager.default.temporaryDirectory.path
        let session = makeSession(workspacePath: workspacePath)

        XCTAssertEqual(OpenCodexAction().folderURL(for: session), URL(fileURLWithPath: workspacePath))
    }

    func testNoActionsWhenSessionHasNoTargets() {
        let session = makeSession()

        XCTAssertNil(OpenCodexAction().threadURLToOpen(for: session))
        XCTAssertNil(OpenCodexAction().folderURL(for: session))
    }

    func testOpenThreadUsesInjectedOpener() {
        let expectedURL = URL(string: "codex://threads/session-1")!
        let session = makeSession(threadURL: expectedURL)
        var openedURL: URL?
        let action = OpenCodexAction(openURL: { openedURL = $0 }, canOpenApplication: { _ in true })

        action.openThread(session)

        XCTAssertEqual(openedURL, expectedURL)
    }

    func testOpenFolderUsesInjectedOpener() {
        let expectedURL = URL(fileURLWithPath: FileManager.default.temporaryDirectory.path)
        let session = makeSession(workspacePath: expectedURL.path)
        var openedURL: URL?
        let action = OpenCodexAction(openURL: { openedURL = $0 })

        action.openFolder(session)

        XCTAssertEqual(openedURL, expectedURL)
    }

    func testRejectsFileThreadURL() {
        let session = makeSession(
            threadURL: URL(string: "file:///tmp/evil.command"),
            workspacePath: nil
        )

        XCTAssertNil(OpenCodexAction(canOpenApplication: { _ in true }).threadURLToOpen(for: session))
    }

    func testAllowsCodexScheme() {
        let session = makeSession(threadURL: URL(string: "codex://threads/abc"))
        let action = OpenCodexAction(canOpenApplication: { _ in true })

        XCTAssertEqual(action.threadURLToOpen(for: session)?.scheme, "codex")
    }

    func testAllowsExistingDirectoryWorkspace() {
        let session = makeSession(
            provider: "claude-code",
            workspacePath: FileManager.default.temporaryDirectory.path
        )

        XCTAssertEqual(OpenCodexAction().folderURL(for: session)?.path.hasPrefix("/"), true)
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
