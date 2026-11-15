import Foundation

public enum ClaudeHookEventMapper {
    /// Maps a Claude Code hook payload to a session state.
    ///
    /// - Parameter notificationType: Matcher argument retained for older Claude versions.
    ///   Current versions also supply notification_type in the payload.
    public static func state(
        from input: [String: Any],
        notificationType: String? = nil,
        now: Date = Date()
    ) -> ClaudeHookEventState? {
        guard let sessionId = input["session_id"] as? String, !sessionId.isEmpty,
              let cwd = input["cwd"] as? String, !cwd.isEmpty,
              let eventName = input["hook_event_name"] as? String else {
            return nil
        }

        // SubagentStart describes a child spawned by the parent. Other child-scoped events
        // share session_id and must not overwrite the main conversation's status file.
        if let agentId = input["agent_id"] as? String, !agentId.isEmpty,
           eventName != "SubagentStart" {
            return nil
        }

        guard let (status, detail) = statusAndDetail(
            eventName: eventName,
            notificationType: (input["notification_type"] as? String) ?? notificationType,
            input: input
        ) else {
            return nil
        }

        return ClaudeHookEventState(
            sessionId: sessionId,
            status: status,
            detail: detail,
            workspacePath: cwd,
            transcriptPath: input["transcript_path"] as? String,
            updatedAt: now,
            completedAt: isTurnCompletion(eventName: eventName) ? now : nil
        )
    }

    /// `Stop` marks the end of a turn — the one discrete, non-flapping "task finished" signal.
    private static func isTurnCompletion(eventName: String) -> Bool {
        eventName == "Stop"
    }

    private static func statusAndDetail(
        eventName: String,
        notificationType: String?,
        input: [String: Any]
    ) -> (AgentStatus, String)? {
        switch eventName {
        case "SessionStart":
            return (.idle, "Claude Code session started")
        case "UserPromptSubmit", "UserPromptExpansion", "PreToolUse", "PostToolUse",
             "PostToolUseFailure", "PostToolBatch", "ElicitationResult",
             "TaskCreated", "SubagentStart":
            return (.working, "Claude Code is working")
        case "PermissionRequest", "Elicitation":
            return (.needsInput, "Claude Code needs permission")
        case "Notification":
            return notificationStatusAndDetail(notificationType: notificationType)
        case "Stop", "SessionEnd":
            return (.idle, "Last Claude Code turn completed")
        case "PermissionDenied", "SubagentStop", "TaskCompleted", "TeammateIdle":
            // The user already responded (denial) or these are local sub-events — leave the
            // session's prior state untouched rather than lighting the attention lamp.
            return nil
        case "StopFailure":
            return (.failed, "Claude Code stop failed")
        default:
            return nil
        }
    }

    /// Only genuine "blocked, needs you" notification types map to `needsInput`.
    /// `idle_prompt` ("your turn") and informational types (`auth_success`,
    /// `elicitation_complete`, `elicitation_response`) must NOT light the attention lamp —
    /// `idle_prompt` in particular can fire after every response.
    private static func notificationStatusAndDetail(notificationType: String?) -> (AgentStatus, String)? {
        switch notificationType {
        case "permission_prompt":
            return (.needsInput, "Claude Code needs permission")
        case "elicitation_dialog":
            return (.needsInput, "Claude Code needs input")
        case "idle_prompt":
            return (.idle, "Claude Code is waiting for your next prompt")
        default:
            // Informational or unknown notification → no state change.
            return nil
        }
    }
}
