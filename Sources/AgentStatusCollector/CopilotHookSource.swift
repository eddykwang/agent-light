import AgentTrafficLightsCore
import Foundation

public struct CopilotHookSource: SessionSource {
    private let eventsRoot: String
    private let now: () -> Date
    private let terminalRetention: TimeInterval
    private let pruneAfter: TimeInterval

    public init(
        eventsRoot: String? = nil,
        now: @escaping () -> Date = Date.init,
        terminalRetention: TimeInterval = 60,
        pruneAfter: TimeInterval = 60 * 60 * 24
    ) {
        self.eventsRoot = eventsRoot
            ?? "\(FileManager.default.homeDirectoryForCurrentUser.path)/.agent-traffic-lights/copilot-hooks"
        self.now = now
        self.terminalRetention = terminalRetention
        self.pruneAfter = pruneAfter
    }

    public func currentSessions() throws -> [RawSession] {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(atPath: eventsRoot) else { return [] }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let currentTime = now()

        return files
            .filter { $0.hasSuffix(".json") }
            .compactMap { file in
                let fileURL = URL(fileURLWithPath: eventsRoot).appendingPathComponent(file)
                guard let data = try? Data(contentsOf: fileURL),
                      let state = try? decoder.decode(CopilotHookEventState.self, from: data),
                      !state.sessionId.isEmpty,
                      !state.workspacePath.isEmpty else {
                    return nil
                }

                let referenceDate = state.endedAt ?? state.updatedAt
                let retention = state.endedAt == nil ? pruneAfter : terminalRetention
                if currentTime.timeIntervalSince(referenceDate) > retention {
                    try? fileManager.removeItem(at: fileURL)
                    return nil
                }

                return RawSession(
                    id: "copilot-cli:\(state.sessionId)",
                    provider: "copilot-cli",
                    projectName: (state.workspacePath as NSString).lastPathComponent,
                    workspacePath: state.workspacePath,
                    threadURL: nil,
                    fileURL: fileURL,
                    status: state.status,
                    detail: state.detail,
                    updatedAt: state.updatedAt,
                    isEventSignal: true,
                    completedAt: state.completedAt
                )
            }
    }
}
