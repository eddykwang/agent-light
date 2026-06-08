import Foundation
import AgentTrafficLightsCore

public enum StatusClassifier {
    /// Classifies a Claude Code session from its most-recent transcript objects.
    /// Field names confirmed by Phase 0 spike (2026-06-06).
    /// Note: needsInput is NOT classifiable from CC transcripts (requires hooks).
    public static func classifyClaudeCode(objects: [[String: Any]]) -> (AgentStatus, String) {
        guard !objects.isEmpty else { return (.unknown, "No transcript entries") }

        // Ignore trailing metadata entries such as permission-mode and hook attachments.
        let lastTurnType = objects.reversed().compactMap { obj -> String? in
            guard let type = obj["type"] as? String else { return nil }
            return ["user", "assistant", "last-prompt"].contains(type) ? type : nil
        }.first

        if lastTurnType == "last-prompt" {
            return (.idle, "Last Claude Code turn completed")
        }

        // Find the last assistant entry to check stop_reason
        let lastAssistant = objects.reversed().first(where: { ($0["type"] as? String) == "assistant" })

        // If the latest turn entry is a user message, the model is mid-turn.
        if lastTurnType == "user" {
            return (.working, "Claude Code is working")
        }

        if let assistant = lastAssistant,
           let message = assistant["message"] as? [String: Any] {
            let stopReason = message["stop_reason"] as? String ?? ""
            switch stopReason {
            case "tool_use":
                return (.working, "Claude Code is working")
            case "end_turn", "stop_sequence":
                return (.idle, "Last Claude Code turn completed")
            case "max_tokens":
                // Model hit the context window limit mid-output; treat as still working
                // (session may need continuation, not a terminal state).
                return (.working, "Claude Code is working")
            default:
                break
            }
        }

        return (.unknown, "Claude Code: unrecognized state")
    }
}

extension StatusClassifier {
    /// Classifies a Codex session from its most-recent rollout objects.
    /// Field names confirmed by Phase 0 spike (2026-06-06).
    /// Note: needsInput and failed are NOT classifiable from Codex rollout JSONL.
    public static func classifyCodex(objects: [[String: Any]]) -> (AgentStatus, String) {
        guard !objects.isEmpty else { return (.unknown, "No rollout entries") }

        // Lifecycle events that determine state (last one wins)
        let lifecycleEvents: Set<String> = ["task_started", "task_complete", "turn_aborted"]

        // Find the last lifecycle event_msg
        var lastLifecycle: String? = nil
        for obj in objects {
            guard (obj["type"] as? String) == "event_msg",
                  let payload = obj["payload"] as? [String: Any],
                  let eventType = payload["type"] as? String,
                  lifecycleEvents.contains(eventType) else { continue }
            lastLifecycle = eventType
        }

        switch lastLifecycle {
        case "task_started":
            return (.working, "Codex is working")
        case "task_complete":
            return (.idle, "Last Codex turn completed")
        case "turn_aborted":
            // User interrupted the turn — not a failure, treated as idle
            return (.idle, "Codex turn was interrupted")
        default:
            return (.unknown, "Codex: no lifecycle event found")
        }
    }
}
