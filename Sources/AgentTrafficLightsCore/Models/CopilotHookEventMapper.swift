import Foundation

public enum CopilotHookEventMapper {
    /// Maps a native camelCase Copilot CLI hook payload into compact local state.
    ///
    /// Copilot's native payload does not consistently carry its event name, so the hook
    /// installer passes `eventName` as argv. `previous` is used to preserve the completion edge
    /// marker and to reject late asynchronous notifications using the payload timestamp.
    public static func state(
        from input: [String: Any],
        eventName: String,
        previous: CopilotHookEventState? = nil,
        now: Date = Date()
    ) -> CopilotHookEventState? {
        guard let sessionId = string(input["sessionId"]) ?? string(input["session_id"]),
              !sessionId.isEmpty else {
            return nil
        }

        let matchingPrevious = previous?.sessionId == sessionId ? previous : nil
        guard let workspacePath = nonEmptyString(input["cwd"]) ?? matchingPrevious?.workspacePath else {
            return nil
        }

        let eventDate = timestamp(from: input["timestamp"]) ?? now
        if let previousDate = matchingPrevious?.updatedAt, eventDate < previousDate {
            return nil
        }

        var completedAt = matchingPrevious?.completedAt
        var endedAt: Date?
        let statusAndDetail: (AgentStatus, String)?

        switch eventName {
        case "sessionStart":
            if nonEmptyString(input["initialPrompt"]) != nil || nonEmptyString(input["initial_prompt"]) != nil {
                statusAndDetail = (.working, "Copilot CLI is working")
            } else {
                statusAndDetail = (.idle, "Copilot CLI session started")
            }

        case "userPromptSubmitted":
            statusAndDetail = (.working, "Copilot CLI is working")

        case "postToolUse", "postToolUseFailure":
            // A tool failure is not a terminal agent failure; Copilot may recover or retry.
            statusAndDetail = (.working, "Copilot CLI is working")

        case "notification":
            switch string(input["notification_type"]) {
            case "permission_prompt":
                statusAndDetail = (.needsInput, "Copilot CLI needs permission")
            case "elicitation_dialog":
                statusAndDetail = (.needsInput, "Copilot CLI needs input")
            default:
                return nil
            }

        case "agentStop":
            completedAt = eventDate
            statusAndDetail = (.idle, "Last Copilot CLI turn completed")

        case "errorOccurred":
            // Recoverable model/tool errors are part of normal agent execution and must not
            // create a red alert. Only an explicit non-recoverable error is terminal enough.
            guard (input["recoverable"] as? Bool) == false else { return nil }
            statusAndDetail = (.failed, "Copilot CLI encountered an unrecoverable error")

        case "sessionEnd":
            endedAt = eventDate
            switch string(input["reason"]) {
            case "complete":
                completedAt = completedAt ?? eventDate
                statusAndDetail = (.idle, "Last Copilot CLI turn completed")
            case "error":
                statusAndDetail = (.failed, "Copilot CLI session ended with an error")
            case "timeout":
                statusAndDetail = (.failed, "Copilot CLI session timed out")
            case "abort":
                statusAndDetail = (.idle, "Copilot CLI session was aborted")
            case "user_exit":
                statusAndDetail = (.idle, "Copilot CLI session ended")
            default:
                statusAndDetail = (.idle, "Copilot CLI session ended")
            }

        default:
            return nil
        }

        guard let (status, detail) = statusAndDetail else { return nil }
        return CopilotHookEventState(
            sessionId: sessionId,
            status: status,
            detail: detail,
            workspacePath: workspacePath,
            updatedAt: eventDate,
            completedAt: completedAt,
            endedAt: endedAt
        )
    }

    private static func timestamp(from value: Any?) -> Date? {
        if let number = value as? NSNumber {
            return Date(timeIntervalSince1970: number.doubleValue / 1_000)
        }
        if let text = value as? String {
            if let milliseconds = Double(text) {
                return Date(timeIntervalSince1970: milliseconds / 1_000)
            }
            return ISO8601DateFormatter().date(from: text)
        }
        return nil
    }

    private static func nonEmptyString(_ value: Any?) -> String? {
        guard let value = string(value)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    private static func string(_ value: Any?) -> String? {
        value as? String
    }
}
