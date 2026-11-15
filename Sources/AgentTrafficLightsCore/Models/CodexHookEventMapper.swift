import Foundation

public enum CodexHookEventMapper {
    public static func state(from input: [String: Any], previous: CodexHookEventState? = nil,
                             now: Date = Date()) -> CodexHookEventState? {
        guard let id = input["session_id"] as? String, !id.isEmpty,
              let cwd = input["cwd"] as? String, !cwd.isEmpty,
              let event = input["hook_event_name"] as? String else { return nil }
        if let agentID = input["agent_id"] as? String, !agentID.isEmpty { return nil }
        let previous = previous?.sessionId == id ? previous : nil
        let turnID = input["turn_id"] as? String
        var completedAt = previous?.completedAt
        var completedTurnID = previous?.completedTurnId
        var endedAt: Date?
        let status: AgentStatus
        let detail: String
        switch event {
        case "SessionStart":
            // Resume/compaction can happen inside an active turn.
            status = previous?.endedAt == nil ? (previous?.status ?? .idle) : .idle
            detail = previous?.endedAt == nil ? (previous?.detail ?? "Codex session started") : "Codex session resumed"
        case "UserPromptSubmit", "PreToolUse", "PostToolUse":
            guard let turnID, !turnID.isEmpty else { return nil }
            if event != "UserPromptSubmit", previous?.completedTurnId == turnID { return nil }
            if event != "UserPromptSubmit", let current = previous?.turnId, current != turnID { return nil }
            if event == "PreToolUse", ["request_user_input", "request_user_input_async"].contains(input["tool_name"] as? String ?? "") {
                status = .needsInput; detail = "Codex needs input"
            } else {
                status = .working; detail = "Codex is working"
            }
        case "PermissionRequest":
            guard let turnID, !turnID.isEmpty else { return nil }
            if let current = previous?.turnId, current != turnID { return nil }
            if previous?.completedTurnId == turnID { return nil }
            status = .needsInput; detail = "Codex needs permission"
        case "Stop":
            guard let turnID, !turnID.isEmpty else { return nil }
            if let current = previous?.turnId, current != turnID { return nil }
            status = .idle; detail = "Last Codex turn completed"
            if completedTurnID != turnID {
                // Shared snapshots encode dates to seconds, so markers must advance by a full second.
                completedAt = max(now, (completedAt ?? .distantPast).addingTimeInterval(1))
                completedTurnID = turnID
            }
        case "Interrupt":
            guard let turnID, !turnID.isEmpty else { return nil }
            if let current = previous?.turnId, current != turnID { return nil }
            status = .idle; detail = "Codex turn was interrupted"
        case "SessionEnd":
            status = .idle; detail = "Codex session ended"; endedAt = now
        default:
            return nil
        }
        return CodexHookEventState(sessionId: id, status: status, detail: detail, workspacePath: cwd,
                                   transcriptPath: input["transcript_path"] as? String ?? previous?.transcriptPath,
                                   updatedAt: now, completedAt: completedAt,
                                   turnId: turnID ?? previous?.turnId, completedTurnId: completedTurnID, endedAt: endedAt)
    }
}
