import Foundation

public struct CopilotHookEventState: Codable, Equatable {
    public let version: Int
    public let sessionId: String
    public let status: AgentStatus
    public let detail: String
    public let workspacePath: String
    public let updatedAt: Date
    /// Advances only when the main Copilot agent completes a turn.
    public let completedAt: Date?
    /// Set by `sessionEnd` so the collector can retain short-lived terminal sessions long
    /// enough for the app's polling loop to observe them.
    public let endedAt: Date?

    public init(
        version: Int = 1,
        sessionId: String,
        status: AgentStatus,
        detail: String,
        workspacePath: String,
        updatedAt: Date,
        completedAt: Date? = nil,
        endedAt: Date? = nil
    ) {
        self.version = version
        self.sessionId = sessionId
        self.status = status
        self.detail = detail
        self.workspacePath = workspacePath
        self.updatedAt = updatedAt
        self.completedAt = completedAt
        self.endedAt = endedAt
    }
}
