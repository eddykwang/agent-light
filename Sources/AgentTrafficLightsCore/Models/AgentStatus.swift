import Foundation

public enum AgentStatus: String, Codable, CaseIterable, Equatable {
    case idle
    case working
    case needsInput
    case failed
    case unknown

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = AgentStatus(rawValue: rawValue) ?? .unknown
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var aggregateRank: Int {
        switch self {
        case .failed, .needsInput:
            return 4
        case .working:
            return 3
        case .idle:
            return 2
        case .unknown:
            return 1
        }
    }

    public var displayName: String {
        switch self {
        case .idle:
            return "Idle"
        case .working:
            return "Working"
        case .needsInput:
            return "Needs input"
        case .failed:
            return "Failed"
        case .unknown:
            return "Unknown"
        }
    }
}
