import Foundation

public enum ClaudeHookEventMapper {
    /// Maps a Claude Code hook payload to a session state.
    ///
    /// - Parameter notificationType: For `Notification` events only. Claude Code does NOT
    ///   put the notification type in the JSON payload — it is selected via the hook `matcher`.
    ///   The hook binary therefore receives the matched type as a command-line argument and
    ///   passes it here. `input["notification_type"]` is used only as a fallback for tests.
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

        let (status, detail) = statusAndDetail(
            eventName: eventName,
            notificationType: notificationType ?? (input["notification_type"] as? String),
            input: input
        )
        return ClaudeHookEventState(
            sessionId: sessionId,
            status: status,
            detail: detail,
            workspacePath: cwd,
            transcriptPath: input["transcript_path"] as? String,
            updatedAt: now
        )
    }

    private static func statusAndDetail(
        eventName: String,
        notificationType: String?,
        input: [String: Any]
    ) -> (AgentStatus, String) {
        switch eventName {
        case "SessionStart":
            return (.idle, "Claude Code session started")
        case "UserPromptSubmit", "UserPromptExpansion", "PreToolUse", "PostToolUse",
             "PostToolUseFailure", "PostToolBatch", "ElicitationResult",
             "TaskCreated", "SubagentStart":
            return (.working, "Claude Code is working")
        case "PermissionRequest", "PermissionDenied", "Elicitation":
            return (.needsInput, "Claude Code needs permission")
        case "Notification":
            return notificationStatusAndDetail(notificationType: notificationType)
        case "Stop", "SubagentStop", "TaskCompleted", "TeammateIdle", "SessionEnd":
            return (.idle, "Last Claude Code turn completed")
        case "StopFailure":
            return (.failed, "Claude Code stop failed")
        default:
            return (.working, "Claude Code is working")
        }
    }

    /// Only genuine "blocked, needs you" notification types map to `needsInput`.
    /// `idle_prompt` ("your turn") and informational types (`auth_success`,
    /// `elicitation_complete`, `elicitation_response`) must NOT light the red lamp —
    /// `idle_prompt` in particular can fire after every response.
    private static func notificationStatusAndDetail(notificationType: String?) -> (AgentStatus, String) {
        switch notificationType {
        case "permission_prompt":
            return (.needsInput, "Claude Code needs permission")
        case "elicitation_dialog":
            return (.needsInput, "Claude Code needs input")
        case "idle_prompt":
            return (.idle, "Claude Code is waiting for your next prompt")
        default:
            // Informational or unknown notification → neutral, never a false red.
            return (.idle, "Claude Code notification")
        }
    }
}
