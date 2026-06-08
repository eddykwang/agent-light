import AgentTrafficLightsCore
import XCTest
@testable import AgentTrafficLights

@MainActor
final class SessionAlertNotifierTests: XCTestCase {
    func testFiresOnlyOnTransitionIntoAttention() {
        var posted: [String] = []
        let notifier = SessionAlertNotifier(post: { title, _ in posted.append(title) })

        notifier.update(aggregate: .working, sessions: [], notifyOnAttention: true, notifyOnSessionCompletion: false, notifyOnAllCompletion: false)
        notifier.update(aggregate: .needsInput, sessions: [], notifyOnAttention: true, notifyOnSessionCompletion: false, notifyOnAllCompletion: false)
        notifier.update(aggregate: .needsInput, sessions: [], notifyOnAttention: true, notifyOnSessionCompletion: false, notifyOnAllCompletion: false)
        notifier.update(aggregate: .failed, sessions: [], notifyOnAttention: true, notifyOnSessionCompletion: false, notifyOnAllCompletion: false)
        notifier.update(aggregate: .idle, sessions: [], notifyOnAttention: true, notifyOnSessionCompletion: false, notifyOnAllCompletion: false)
        notifier.update(aggregate: .needsInput, sessions: [], notifyOnAttention: true, notifyOnSessionCompletion: false, notifyOnAllCompletion: false)

        XCTAssertEqual(posted.count, 3)
    }

    func testFiresOnAggregateWorkingToIdleWhenAllCompletionNotificationsAreEnabled() {
        var posted: [String] = []
        let notifier = SessionAlertNotifier(post: { title, _ in posted.append(title) })

        notifier.update(aggregate: .idle, sessions: [], notifyOnAttention: false, notifyOnSessionCompletion: false, notifyOnAllCompletion: true)
        notifier.update(aggregate: .working, sessions: [session(id: "a", status: .working)], notifyOnAttention: false, notifyOnSessionCompletion: false, notifyOnAllCompletion: true)
        notifier.update(aggregate: .working, sessions: [session(id: "a", status: .working)], notifyOnAttention: false, notifyOnSessionCompletion: false, notifyOnAllCompletion: true)
        notifier.update(aggregate: .idle, sessions: [session(id: "a", status: .idle)], notifyOnAttention: false, notifyOnSessionCompletion: false, notifyOnAllCompletion: true)
        notifier.update(aggregate: .idle, sessions: [session(id: "a", status: .idle)], notifyOnAttention: false, notifyOnSessionCompletion: false, notifyOnAllCompletion: true)
        notifier.update(aggregate: .working, sessions: [session(id: "a", status: .working)], notifyOnAttention: false, notifyOnSessionCompletion: false, notifyOnAllCompletion: true)
        notifier.update(aggregate: .failed, sessions: [session(id: "a", status: .failed)], notifyOnAttention: false, notifyOnSessionCompletion: false, notifyOnAllCompletion: true)
        notifier.update(aggregate: .idle, sessions: [session(id: "a", status: .idle)], notifyOnAttention: false, notifyOnSessionCompletion: false, notifyOnAllCompletion: true)
        notifier.update(aggregate: .working, sessions: [session(id: "a", status: .working)], notifyOnAttention: false, notifyOnSessionCompletion: false, notifyOnAllCompletion: true)
        notifier.update(aggregate: .idle, sessions: [session(id: "a", status: .idle)], notifyOnAttention: false, notifyOnSessionCompletion: false, notifyOnAllCompletion: true)

        XCTAssertEqual(posted, ["All agents are idle", "All agents are idle"])
    }

    func testDoesNotFireAggregateCompletionWhenAllCompletionNotificationsAreDisabled() {
        var posted: [String] = []
        let notifier = SessionAlertNotifier(post: { title, _ in posted.append(title) })

        notifier.update(aggregate: .working, sessions: [session(id: "a", status: .working)], notifyOnAttention: false, notifyOnSessionCompletion: false, notifyOnAllCompletion: false)
        notifier.update(aggregate: .idle, sessions: [session(id: "a", status: .idle)], notifyOnAttention: false, notifyOnSessionCompletion: false, notifyOnAllCompletion: false)

        XCTAssertTrue(posted.isEmpty)
    }

    func testFiresWhenIndividualSessionMovesFromWorkingToIdle() {
        var posted: [String] = []
        let notifier = SessionAlertNotifier(post: { title, _ in posted.append(title) })

        notifier.update(
            aggregate: .working,
            sessions: [
                session(id: "garden", projectName: "Demo API", status: .working),
                session(id: "trains", projectName: "Demo Website", status: .working)
            ],
            notifyOnAttention: false,
            notifyOnSessionCompletion: true,
            notifyOnAllCompletion: false
        )
        notifier.update(
            aggregate: .working,
            sessions: [
                session(id: "garden", projectName: "Demo API", status: .idle),
                session(id: "trains", projectName: "Demo Website", status: .working)
            ],
            notifyOnAttention: false,
            notifyOnSessionCompletion: true,
            notifyOnAllCompletion: false
        )
        notifier.update(
            aggregate: .working,
            sessions: [
                session(id: "garden", projectName: "Demo API", status: .idle),
                session(id: "trains", projectName: "Demo Website", status: .working)
            ],
            notifyOnAttention: false,
            notifyOnSessionCompletion: true,
            notifyOnAllCompletion: false
        )

        XCTAssertEqual(posted, ["Codex finished: Demo API"])
    }

    func testFiresWhenWorkingSessionDisappearsAfterCompletion() {
        var posted: [String] = []
        let notifier = SessionAlertNotifier(post: { title, _ in posted.append(title) })

        notifier.update(
            aggregate: .working,
            sessions: [session(id: "garden", projectName: "Demo API", status: .working)],
            notifyOnAttention: false,
            notifyOnSessionCompletion: true,
            notifyOnAllCompletion: false
        )
        notifier.update(
            aggregate: .idle,
            sessions: [],
            notifyOnAttention: false,
            notifyOnSessionCompletion: true,
            notifyOnAllCompletion: false
        )

        XCTAssertEqual(posted, ["Codex finished: Demo API"])
    }

    func testFiresWhenOneWorkingSessionDisappearsWhileAnotherKeepsWorking() {
        var posted: [String] = []
        let notifier = SessionAlertNotifier(post: { title, _ in posted.append(title) })

        notifier.update(
            aggregate: .working,
            sessions: [
                session(id: "garden", projectName: "Demo API", status: .working),
                session(id: "trains", projectName: "Demo Website", status: .working)
            ],
            notifyOnAttention: false,
            notifyOnSessionCompletion: true,
            notifyOnAllCompletion: false
        )
        notifier.update(
            aggregate: .working,
            sessions: [session(id: "trains", projectName: "Demo Website", status: .working)],
            notifyOnAttention: false,
            notifyOnSessionCompletion: true,
            notifyOnAllCompletion: false
        )

        XCTAssertEqual(posted, ["Codex finished: Demo API"])
    }

    func testDoesNotFireIndividualCompletionWhenDisabled() {
        var posted: [String] = []
        let notifier = SessionAlertNotifier(post: { title, _ in posted.append(title) })

        notifier.update(aggregate: .working, sessions: [session(id: "a", status: .working)], notifyOnAttention: false, notifyOnSessionCompletion: false, notifyOnAllCompletion: false)
        notifier.update(aggregate: .idle, sessions: [session(id: "a", status: .idle)], notifyOnAttention: false, notifyOnSessionCompletion: false, notifyOnAllCompletion: false)

        XCTAssertTrue(posted.isEmpty)
    }

    func testDuplicateSessionIDsDoNotCrashNotifier() {
        var posted: [String] = []
        let notifier = SessionAlertNotifier(post: { title, _ in posted.append(title) })

        notifier.update(
            aggregate: .working,
            sessions: [
                session(id: "duplicate", projectName: "Older", status: .working),
                session(id: "duplicate", projectName: "Newer", status: .working)
            ],
            notifyOnAttention: false,
            notifyOnSessionCompletion: true,
            notifyOnAllCompletion: false
        )
        notifier.update(
            aggregate: .idle,
            sessions: [
                session(id: "duplicate", projectName: "Newer", status: .idle)
            ],
            notifyOnAttention: false,
            notifyOnSessionCompletion: true,
            notifyOnAllCompletion: false
        )

        XCTAssertEqual(posted, ["Codex finished: Newer"])
    }

    func testIndividualCompletionBodyIncludesDetailAndWorkspace() {
        var posted: [(String, String)] = []
        let notifier = SessionAlertNotifier(post: { title, body in posted.append((title, body)) })
        let workspacePath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/garden-copilot")
            .path

        notifier.update(
            aggregate: .working,
            sessions: [
                session(
                    id: "garden",
                    provider: "claude-code",
                    projectName: "Garden Copilot",
                    status: .working,
                    detail: "Claude Code is working",
                    workspacePath: workspacePath
                )
            ],
            notifyOnAttention: false,
            notifyOnSessionCompletion: true,
            notifyOnAllCompletion: false
        )
        notifier.update(
            aggregate: .idle,
            sessions: [
                session(
                    id: "garden",
                    provider: "claude-code",
                    projectName: "Garden Copilot",
                    status: .idle,
                    detail: "Last Claude Code turn completed",
                    workspacePath: workspacePath
                )
            ],
            notifyOnAttention: false,
            notifyOnSessionCompletion: true,
            notifyOnAllCompletion: false
        )

        XCTAssertEqual(posted.map(\.0), ["Claude Code finished: Garden Copilot"])
        XCTAssertEqual(posted.map(\.1), ["Last Claude Code turn completed Workspace: ~/Documents/garden-copilot"])
    }

    func testAttentionNotificationNamesAgentProjectAndReason() {
        var posted: [(String, String)] = []
        let notifier = SessionAlertNotifier(post: { title, body in posted.append((title, body)) })
        let workspacePath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/garden-copilot")
            .path

        notifier.update(
            aggregate: .needsInput,
            sessions: [
                session(
                    id: "garden",
                    provider: "claude-code",
                    projectName: "Garden Copilot",
                    status: .needsInput,
                    detail: "Claude Code needs permission",
                    workspacePath: workspacePath
                )
            ],
            notifyOnAttention: true,
            notifyOnSessionCompletion: false,
            notifyOnAllCompletion: false
        )

        XCTAssertEqual(posted.map(\.0), ["Claude Code needs input: Garden Copilot"])
        XCTAssertEqual(posted.map(\.1), ["Claude Code needs permission Workspace: ~/Documents/garden-copilot"])
    }

    private func session(
        id: String,
        provider: String = "codex",
        projectName: String = "Project",
        status: AgentStatus,
        detail: String? = nil,
        workspacePath: String? = nil
    ) -> AgentSession {
        AgentSession(
            id: id,
            provider: provider,
            projectName: projectName,
            status: status,
            detail: detail,
            workspacePath: workspacePath,
            threadURL: nil,
            updatedAt: nil
        )
    }
}
