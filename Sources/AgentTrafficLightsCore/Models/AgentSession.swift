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

    public init(id: String, provider: String, projectName: String, status: AgentStatus,
                detail: String?, workspacePath: String?, threadURL: URL?, updatedAt: Date?) {
        self.id = id
        self.provider = provider
        self.projectName = projectName
        self.status = status
        self.detail = detail
        self.workspacePath = workspacePath
        self.threadURL = threadURL
        self.updatedAt = updatedAt
    }

    public enum CodingKeys: String, CodingKey {
        case id, provider, projectName, status, detail, workspacePath
        case threadURL = "threadUrl"
        case updatedAt
    }
}
