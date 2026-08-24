import AgentTrafficLightsCore
import Foundation
@preconcurrency import UserNotifications

@MainActor
final class SessionAlertNotifier {
    private var lastAttentionFingerprint: String?
    private var lastAggregateStatus: AgentStatus?
    private var lastSessionsByID: [String: AgentSession] = [:]
    private let foregroundPresenter = NotificationForegroundPresenter()
    private let post: (String, String) -> Void

    init(post: ((String, String) -> Void)? = nil) {
        self.post = post ?? { title, body in
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: "agent-traffic-lights-\(UUID().uuidString)",
                content: content,
                trigger: nil
            )
            UNUserNotificationCenter.current().add(request)
        }

        if post == nil {
            UNUserNotificationCenter.current().delegate = foregroundPresenter
            prepareNotificationAuthorization()
        }
    }

    func update(
        aggregate status: AgentStatus,
        sessions: [AgentSession],
        notifyOnAttention: Bool,
        notifyOnSessionCompletion: Bool,
        notifyOnAllCompletion: Bool
    ) {
        let didFinish = shouldPostAllCompletion(aggregateStatus: status, sessions: sessions)

        if notifyOnSessionCompletion {
            postFinishedSessions(sessions, aggregateStatus: status)
        }

        if notifyOnAllCompletion && didFinish {
            post("All agents are idle", allIdleBody(currentSessions: sessions))
        }

        updateAttentionStatus(status, sessions: sessions, notifyOnAttention: notifyOnAttention)
        lastAggregateStatus = status
        lastSessionsByID = sessionsByID(sessions)
    }

    private func postFinishedSessions(_ sessions: [AgentSession], aggregateStatus: AgentStatus) {
        let currentSessionsByID = sessionsByID(sessions)

        for session in sessions {
            guard shouldPostCompletion(for: session, previous: lastSessionsByID[session.id]) else {
                continue
            }
            post(completionTitle(for: session), completionBody(for: session))
        }

        guard aggregateStatus != .unknown else {
            return
        }

        for previousSession in lastSessionsByID.values {
            guard !usesCompletionMarker(provider: previousSession.provider),
                  previousSession.status == .working,
                  currentSessionsByID[previousSession.id] == nil else {
                continue
            }
            post(completionTitle(for: previousSession), disappearedCompletionBody(for: previousSession))
        }
    }

    private func shouldPostCompletion(for session: AgentSession, previous: AgentSession?) -> Bool {
        guard let previous else {
            return false
        }

        if usesCompletionMarker(provider: session.provider) {
            // Edge-trigger on the provider's discrete completion marker: fire exactly once when a
            // strictly newer `completedAt` appears. This is immune to working/idle flapping and
            // fires the moment the turn ends instead of waiting for a later idle observation.
            guard let completedAt = session.completedAt else { return false }
            guard let previousCompletedAt = previous.completedAt else { return true }
            return completedAt > previousCompletedAt
        }

        return previous.status == .working && session.status == .idle
    }

    private func shouldPostAllCompletion(aggregateStatus status: AgentStatus, sessions: [AgentSession]) -> Bool {
        guard lastAggregateStatus == .working, status == .idle else {
            return false
        }

        let currentSessionsByID = sessionsByID(sessions)
        for session in sessions where shouldPostCompletion(for: session, previous: lastSessionsByID[session.id]) {
            return true
        }

        return lastSessionsByID.values.contains { previousSession in
            !usesCompletionMarker(provider: previousSession.provider)
                && previousSession.status == .working
                && currentSessionsByID[previousSession.id] == nil
        }
    }

    private func sessionsByID(_ sessions: [AgentSession]) -> [String: AgentSession] {
        var result: [String: AgentSession] = [:]
        for session in sessions {
            result[session.id] = session
        }
        return result
    }

    private func updateAttentionStatus(_ status: AgentStatus, sessions: [AgentSession], notifyOnAttention: Bool) {
        guard notifyOnAttention, status.requiresAttention else {
            lastAttentionFingerprint = nil
            return
        }

        let session = sessions.first { $0.status == .failed }
            ?? sessions.first { $0.status == .needsInput }
        let fingerprint = "\(session?.id ?? "aggregate"):\(status.rawValue)"

        if lastAttentionFingerprint != fingerprint {
            post(attentionTitle(status: status, session: session), attentionBody(status: status, session: session))
        }
        lastAttentionFingerprint = fingerprint
    }

    private func completionTitle(for session: AgentSession) -> String {
        "\(providerName(for: session.provider)) finished: \(session.projectName)"
    }

    private func completionBody(for session: AgentSession) -> String {
        compactBody(parts: [
            cleanedDetail(session.detail, fallback: "Session is idle."),
            workspaceSummary(for: session)
        ])
    }

    private func disappearedCompletionBody(for session: AgentSession) -> String {
        compactBody(parts: [
            "Session is no longer active.",
            workspaceSummary(for: session)
        ])
    }

    private func allIdleBody(currentSessions sessions: [AgentSession]) -> String {
        let workingCount = lastSessionsByID.values.filter { $0.status == .working }.count
        let idleCount = sessions.filter { $0.status == .idle }.count

        if workingCount > 0 {
            return workingCount == 1
                ? "The last working agent finished."
                : "\(workingCount) working agents finished."
        }

        if idleCount > 0 {
            return idleCount == 1
                ? "1 visible agent is idle."
                : "\(idleCount) visible agents are idle."
        }

        return "No visible agents are working."
    }

    private func attentionTitle(status: AgentStatus, session: AgentSession?) -> String {
        guard let session else {
            return status == .failed ? "An agent failed" : "An agent needs attention"
        }

        let provider = providerName(for: session.provider)
        return status == .failed
            ? "\(provider) failed: \(session.projectName)"
            : "\(provider) needs input: \(session.projectName)"
    }

    private func attentionBody(status: AgentStatus, session: AgentSession?) -> String {
        guard let session else {
            return status == .failed
                ? "A visible agent reported a failure."
                : "A visible agent is waiting for permission or input."
        }

        let fallback = status == .failed ? "The agent reported a failure." : "The agent is waiting for permission or input."
        return compactBody(parts: [
            cleanedDetail(session.detail, fallback: fallback),
            workspaceSummary(for: session)
        ])
    }

    private func providerName(for provider: String) -> String {
        switch provider {
        case "claude-code":
            return "Claude Code"
        case "codex":
            return "Codex"
        case "copilot-cli":
            return "Copilot CLI"
        default:
            return provider
        }
    }

    private func usesCompletionMarker(provider: String) -> Bool {
        provider == "claude-code" || provider == "copilot-cli"
    }

    private func cleanedDetail(_ detail: String?, fallback: String) -> String {
        guard let detail, !detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return fallback
        }
        return detail
    }

    private func workspaceSummary(for session: AgentSession) -> String? {
        guard let path = session.workspacePath, !path.isEmpty else {
            return nil
        }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path == home {
            return "Workspace: ~"
        }
        if path.hasPrefix(home + "/") {
            return "Workspace: ~/" + String(path.dropFirst(home.count + 1))
        }
        return "Workspace: \(path)"
    }

    private func compactBody(parts: [String?]) -> String {
        parts
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func prepareNotificationAuthorization() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else {
                return
            }
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }
}

private final class NotificationForegroundPresenter: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

private extension AgentStatus {
    var requiresAttention: Bool {
        self == .needsInput || self == .failed
    }
}
