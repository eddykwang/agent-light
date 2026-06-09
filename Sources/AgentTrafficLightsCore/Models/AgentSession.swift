import Foundation

public struct AgentSession: Codable, Equatable, Identifiable {
    public let id: String
    public let provider: String
    public let projectName: String
    public let status: AgentStatus
    public let detail: String?
    public let workspacePath: String?
    public let threadURL: URL?
    public let updatedAt: Date?
    /// Set only by a discrete turn-completion event (the Claude Code `Stop` hook). It is a
    /// monotonic, edge-triggered marker — independent of the wobble-prone `status` field — so
    /// notifiers can fire "task finished" exactly once per turn without debouncing.
    public let completedAt: Date?

    public init(id: String, provider: String, projectName: String, status: AgentStatus,
                detail: String?, workspacePath: String?, threadURL: URL?, updatedAt: Date?,
                completedAt: Date? = nil) {
        self.id = id
        self.provider = provider
        self.projectName = projectName
        self.status = status
        self.detail = detail
        self.workspacePath = workspacePath
        self.threadURL = threadURL
        self.updatedAt = updatedAt
        self.completedAt = completedAt
    }

    public enum CodingKeys: String, CodingKey {
        case id, provider, projectName, status, detail, workspacePath
        case threadURL = "threadUrl"
        case updatedAt
        case completedAt
    }

    /// Returns a copy with `completedAt` replaced — used when merging duplicate sessions so the
    /// completion marker survives even when a different session wins the workspace dedup.
    public func withCompletedAt(_ value: Date?) -> AgentSession {
        AgentSession(id: id, provider: provider, projectName: projectName, status: status,
                     detail: detail, workspacePath: workspacePath, threadURL: threadURL,
                     updatedAt: updatedAt, completedAt: value)
    }
}
