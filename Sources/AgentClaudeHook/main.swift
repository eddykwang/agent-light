import Foundation
import AgentTrafficLightsCore

let inputData = FileHandle.standardInput.readDataToEndOfFile()
guard !inputData.isEmpty,
      let json = try? JSONSerialization.jsonObject(with: inputData) as? [String: Any] else {
    exit(0)
}

let root = ProcessInfo.processInfo.environment["AGENT_LIGHT_CLAUDE_HOOKS_DIR"]
    ?? "\(FileManager.default.homeDirectoryForCurrentUser.path)/.agent-traffic-lights/claude-hooks"
let rootURL = URL(fileURLWithPath: root, isDirectory: true)

// Notification type is delivered via the hook matcher, NOT the JSON payload, so the
// installer passes it as the first CLI argument (e.g. "permission_prompt").
let notificationType = CommandLine.arguments.dropFirst().first

guard let state = ClaudeHookEventMapper.state(from: json, notificationType: notificationType) else {
    exit(0)
}

let fileURL = rootURL.appendingPathComponent("\(safeFileName(state.sessionId)).json")

// On session end, remove the signal file rather than leaving a stale marker behind.
if (json["hook_event_name"] as? String) == "SessionEnd" {
    try? FileManager.default.removeItem(at: fileURL)
    exit(0)
}

do {
    try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(state)
    try data.write(to: fileURL, options: .atomic)
} catch {
    exit(0)
}

func safeFileName(_ value: String) -> String {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
    let scalars = value.unicodeScalars.map { scalar in
        allowed.contains(scalar) ? Character(scalar) : "-"
    }
    let name = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    return name.isEmpty ? "session" : name
}
