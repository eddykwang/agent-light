import AgentTrafficLightsCore
import Darwin
import Foundation

let inputData = FileHandle.standardInput.readDataToEndOfFile()
guard !inputData.isEmpty,
      let input = try? JSONSerialization.jsonObject(with: inputData) as? [String: Any],
      let eventName = CommandLine.arguments.dropFirst().first,
      !eventName.isEmpty else {
    exit(0)
}

let root = ProcessInfo.processInfo.environment["AGENT_LIGHT_COPILOT_HOOKS_DIR"]
    ?? "\(FileManager.default.homeDirectoryForCurrentUser.path)/.agent-traffic-lights/copilot-hooks"
let rootURL = URL(fileURLWithPath: root, isDirectory: true)
let sessionId = (input["sessionId"] as? String) ?? (input["session_id"] as? String) ?? "session"
let fileURL = rootURL.appendingPathComponent("\(safeFileName(sessionId)).json")

do {
    try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
} catch {
    exit(0)
}

let lockURL = rootURL.appendingPathComponent(".lock")
let lockDescriptor = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
guard lockDescriptor >= 0 else { exit(0) }
defer { close(lockDescriptor) }
guard flock(lockDescriptor, LOCK_EX) == 0 else { exit(0) }
defer { flock(lockDescriptor, LOCK_UN) }

let decoder = JSONDecoder()
decoder.dateDecodingStrategy = .iso8601
let previous: CopilotHookEventState?
if let previousData = try? Data(contentsOf: fileURL) {
    previous = try? decoder.decode(CopilotHookEventState.self, from: previousData)
} else {
    previous = nil
}

guard let state = CopilotHookEventMapper.state(
    from: input,
    eventName: eventName,
    previous: previous
) else {
    exit(0)
}

do {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(state).write(to: fileURL, options: .atomic)
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
