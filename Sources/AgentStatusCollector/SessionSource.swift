import Foundation
import AgentTrafficLightsCore

/// A session as observed by a source, before liveness filtering.
public struct RawSession: Equatable {
    public let id: String
    public let provider: String
    public let projectName: String
    public let workspacePath: String
    public let threadURL: URL?
    /// The transcript/rollout file URL, used exclusively by `LivenessFilter` implementations.
    /// This field is collector-internal and is NOT persisted to `AgentSession` or `status.json`.
    public let fileURL: URL
    /// Event signal sources (such as Claude Code hooks) already encode the latest known
    /// lifecycle state. Liveness should trust them until their source prunes them.
    public let isEventSignal: Bool
    public let status: AgentStatus
    public let detail: String
    public let updatedAt: Date

    public init(id: String, provider: String, projectName: String, workspacePath: String,
                threadURL: URL?, fileURL: URL, status: AgentStatus, detail: String, updatedAt: Date,
                isEventSignal: Bool = false) {
        self.id = id
        self.provider = provider
        self.projectName = projectName
        self.workspacePath = workspacePath
        self.threadURL = threadURL
        self.fileURL = fileURL
        self.isEventSignal = isEventSignal
        self.status = status
        self.detail = detail
        self.updatedAt = updatedAt
    }

    /// Converts to `AgentSession` for writing to `status.json`.
    /// Note: `fileURL` is intentionally dropped — it is a collector-internal liveness detail.
    public func toAgentSession() -> AgentSession {
        AgentSession(id: id, provider: provider, projectName: projectName, status: status,
                     detail: detail, workspacePath: workspacePath, threadURL: threadURL, updatedAt: updatedAt)
    }

}

public protocol SessionSource {
    func currentSessions() throws -> [RawSession]
}
