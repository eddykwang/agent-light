import AgentTrafficLightsCore
import Darwin
import Foundation

// Observation only: never return a permission decision or continuation instruction.
func collectEvent() {
    let data = FileHandle.standardInput.readDataToEndOfFile()
    guard let input = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let id = input["session_id"] as? String, !id.isEmpty else { return }
    let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["AGENT_LIGHT_CODEX_HOOKS_DIR"]
        ?? "\(FileManager.default.homeDirectoryForCurrentUser.path)/.agent-traffic-lights/codex-hooks", isDirectory: true)
    do { try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) } catch { return }
    let descriptor = open(root.appendingPathComponent(".lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
    guard descriptor >= 0 else { return }
    defer { close(descriptor) }
    guard flock(descriptor, LOCK_EX) == 0 else { return }
    defer { flock(descriptor, LOCK_UN) }
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
    let name = String(String.UnicodeScalarView(id.unicodeScalars.map { allowed.contains($0) ? $0 : "-" }))
    let file = root.appendingPathComponent("\(name).json")
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .millisecondsSince1970
    let previous = (try? Data(contentsOf: file)).flatMap { try? decoder.decode(CodexHookEventState.self, from: $0) }
    guard let state = CodexHookEventMapper.state(from: input, previous: previous) else { return }
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .millisecondsSince1970
    if let encoded = try? encoder.encode(state) { try? encoded.write(to: file, options: .atomic) }

}
collectEvent()
print("{}")
