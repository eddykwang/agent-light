import Foundation

public struct ClaudeHookEventState: Codable, Equatable {
    public let version: Int
    public let sessionId: String
    public let status: AgentStatus
    public let detail: String
    public let workspacePath: String
    public let transcriptPath: String?
    public let updatedAt: Date

    public init(
        version: Int = 1,
        sessionId: String,
        status: AgentStatus,
        detail: String,
        workspacePath: String,
        transcriptPath: String?,
        updatedAt: Date
    ) {
        self.version = version
        self.sessionId = sessionId
        self.status = status
        self.detail = detail
        self.workspacePath = workspacePath
        self.transcriptPath = transcriptPath
        self.updatedAt = updatedAt
    }
}
