import Foundation
import AgentTrafficLightsCore

struct StatusParser {
    struct ParseFailure: LocalizedError, Equatable {
        let message: String

        var errorDescription: String? {
            message
        }
    }

    func parse(data: Data) -> Result<StatusSnapshot, ParseFailure> {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            let decoded = try decoder.decode(StatusSnapshot.self, from: data)
            return .success(deduplicated(decoded))
        } catch {
            return .failure(ParseFailure(message: error.localizedDescription))
        }
    }

    private func deduplicated(_ snapshot: StatusSnapshot) -> StatusSnapshot {
        var sessionsByKey: [String: AgentSession] = [:]
        var orderedKeys: [String] = []

        for session in snapshot.sessions {
            let key = deduplicationKey(for: session)

            guard let existing = sessionsByKey[key] else {
                sessionsByKey[key] = session
                orderedKeys.append(key)
                continue
            }

            let existingDate = existing.updatedAt ?? .distantPast
            let candidateDate = session.updatedAt ?? .distantPast

            if candidateDate >= existingDate {
                sessionsByKey[key] = session
            }
        }

        return StatusSnapshot(
            version: snapshot.version,
            updatedAt: snapshot.updatedAt,
            sessions: orderedKeys.compactMap { sessionsByKey[$0] }
        )
    }

    private func deduplicationKey(for session: AgentSession) -> String {
        if session.provider == "claude-code", let workspacePath = session.workspacePath?.normalizedPathForDeduplication {
            return "\(session.provider):\(workspacePath)"
        }

        return "\(session.provider):\(session.id)"
    }
}

private extension String {
    var normalizedPathForDeduplication: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let normalized = URL(fileURLWithPath: trimmed).standardizedFileURL.path
        return normalized == "/" ? normalized : normalized.trimmingTrailingSlashes()
    }

    func trimmingTrailingSlashes() -> String {
        var value = self
        while value.count > 1, value.hasSuffix("/") {
            value.removeLast()
        }
        return value
    }
}
