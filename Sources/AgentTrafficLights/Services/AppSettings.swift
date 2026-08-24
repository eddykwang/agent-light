import Foundation

enum AgentIntegration: String, CaseIterable, Identifiable {
    case claudeCode
    case copilotCLI

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .copilotCLI: return "Copilot CLI"
        }
    }
}

enum TrafficLightOrientation: String, Codable, CaseIterable, Identifiable {
    case vertical
    case horizontal

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .vertical:
            return "Vertical"
        case .horizontal:
            return "Horizontal"
        }
    }
}

struct DesktopLightPosition: Equatable {
    let x: Double
    let y: Double
}

enum DesktopLightScaleLimits {
    static let minimum = 0.75
    static let maximum = 2.0
    static let defaultValue = 1.0

    static func clamped(_ value: Double) -> Double {
        min(max(value, minimum), maximum)
    }
}

enum CompletionNotificationMode: String, Codable, CaseIterable, Identifiable {
    case off
    case individual
    case allAgentsIdle

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .off:
            return "Off"
        case .individual:
            return "Individual"
        case .allAgentsIdle:
            return "All idle"
        }
    }

    var description: String {
        switch self {
        case .off:
            return "Do not send completion notifications."
        case .individual:
            return "Notify when Codex or a hook-enabled agent completes a turn."
        case .allAgentsIdle:
            return "Notify when all visible agents have reached an idle completion state."
        }
    }
}

enum ClaudeCodeStatusMode: String, Codable, CaseIterable, Identifiable {
    case automatic
    case hooks

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .automatic:
            return "Transcript"
        case .hooks:
            return "Hooks"
        }
    }

    var description: String {
        switch self {
        case .automatic:
            return "Read Claude Code transcripts and local process state. No Claude settings changes."
        case .hooks:
            return "Use Claude Code hooks for precise working, permission, input, and completion events."
        }
    }
}

final class AppSettings: ObservableObject {
    private enum Keys {
        static let orientation = "trafficLightOrientation"
        static let statusFilePath = "statusFilePath"
        static let claudeCodeStatusMode = "claudeCodeStatusMode"
        static let notificationsEnabled = "notificationsEnabled"
        static let alertsEnabled = "alertsEnabled"
        static let notifyOnAttention = "notifyOnAttention"
        static let completionNotificationMode = "completionNotificationMode"
        static let notifyOnSessionCompletion = "notifyOnSessionCompletion"
        static let notifyOnCompletion = "notifyOnCompletion"
        static let launchAtLogin = "launchAtLogin"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let desktopLightVisible = "desktopLightVisible"
        static let desktopLightPositionX = "desktopLightPositionX"
        static let desktopLightPositionY = "desktopLightPositionY"
        static let desktopLightScale = "desktopLightScale"
    }

    private let defaults: UserDefaults

    @Published var orientation: TrafficLightOrientation {
        didSet {
            defaults.set(orientation.rawValue, forKey: Keys.orientation)
        }
    }

    @Published var statusFilePath: String {
        didSet {
            defaults.set(statusFilePath, forKey: Keys.statusFilePath)
        }
    }

    @Published var claudeCodeStatusMode: ClaudeCodeStatusMode {
        didSet {
            defaults.set(claudeCodeStatusMode.rawValue, forKey: Keys.claudeCodeStatusMode)
        }
    }

    @Published var notificationsEnabled: Bool {
        didSet {
            defaults.set(notificationsEnabled, forKey: Keys.notificationsEnabled)
        }
    }

    @Published var alertsEnabled: Bool {
        didSet {
            defaults.set(alertsEnabled, forKey: Keys.alertsEnabled)
            if notifyOnAttention != alertsEnabled {
                notifyOnAttention = alertsEnabled
            }
        }
    }

    @Published var notifyOnAttention: Bool {
        didSet {
            defaults.set(notifyOnAttention, forKey: Keys.notifyOnAttention)
            if alertsEnabled != notifyOnAttention {
                alertsEnabled = notifyOnAttention
            }
        }
    }

    @Published var completionNotificationMode: CompletionNotificationMode {
        didSet {
            defaults.set(completionNotificationMode.rawValue, forKey: Keys.completionNotificationMode)
            defaults.set(completionNotificationMode == .individual, forKey: Keys.notifyOnSessionCompletion)
            defaults.set(completionNotificationMode == .allAgentsIdle, forKey: Keys.notifyOnCompletion)
        }
    }

    var notifyOnCompletion: Bool {
        completionNotificationMode == .allAgentsIdle
    }

    var notifyOnSessionCompletion: Bool {
        completionNotificationMode == .individual
    }

    @Published var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: Keys.launchAtLogin)
        }
    }

    @Published var hasCompletedOnboarding: Bool {
        didSet {
            defaults.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding)
        }
    }

    @Published var desktopLightVisible: Bool {
        didSet {
            defaults.set(desktopLightVisible, forKey: Keys.desktopLightVisible)
        }
    }

    var desktopLightPosition: DesktopLightPosition? {
        get {
            guard defaults.object(forKey: Keys.desktopLightPositionX) != nil,
                  defaults.object(forKey: Keys.desktopLightPositionY) != nil else {
                return nil
            }

            return DesktopLightPosition(
                x: defaults.double(forKey: Keys.desktopLightPositionX),
                y: defaults.double(forKey: Keys.desktopLightPositionY)
            )
        }
        set {
            guard let newValue else {
                defaults.removeObject(forKey: Keys.desktopLightPositionX)
                defaults.removeObject(forKey: Keys.desktopLightPositionY)
                return
            }

            defaults.set(newValue.x, forKey: Keys.desktopLightPositionX)
            defaults.set(newValue.y, forKey: Keys.desktopLightPositionY)
        }
    }

    var desktopLightScale: Double {
        get {
            guard defaults.object(forKey: Keys.desktopLightScale) != nil else {
                return DesktopLightScaleLimits.defaultValue
            }
            return DesktopLightScaleLimits.clamped(defaults.double(forKey: Keys.desktopLightScale))
        }
        set {
            defaults.set(
                DesktopLightScaleLimits.clamped(newValue),
                forKey: Keys.desktopLightScale
            )
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let storedOrientation = defaults.string(forKey: Keys.orientation)
            .flatMap(TrafficLightOrientation.init(rawValue:))
        self.orientation = storedOrientation ?? .vertical

        self.statusFilePath = defaults.string(forKey: Keys.statusFilePath)
            ?? Self.defaultStatusFilePath
        self.claudeCodeStatusMode = defaults.string(forKey: Keys.claudeCodeStatusMode)
            .flatMap(ClaudeCodeStatusMode.init(rawValue:))
            ?? .automatic

        self.notificationsEnabled = defaults.object(forKey: Keys.notificationsEnabled) as? Bool ?? true
        let storedNotificationPreference =
            defaults.object(forKey: Keys.notifyOnAttention) as? Bool
            ?? defaults.object(forKey: Keys.alertsEnabled) as? Bool
            ?? true
        self.alertsEnabled = storedNotificationPreference
        self.notifyOnAttention = storedNotificationPreference
        self.completionNotificationMode = Self.loadCompletionNotificationMode(defaults: defaults)
        self.launchAtLogin = defaults.object(forKey: Keys.launchAtLogin) as? Bool ?? false
        self.hasCompletedOnboarding = defaults.object(forKey: Keys.hasCompletedOnboarding) as? Bool ?? false
        self.desktopLightVisible = defaults.object(forKey: Keys.desktopLightVisible) as? Bool ?? false
    }

    private static func loadCompletionNotificationMode(defaults: UserDefaults) -> CompletionNotificationMode {
        if let rawMode = defaults.string(forKey: Keys.completionNotificationMode),
           let mode = CompletionNotificationMode(rawValue: rawMode) {
            return mode
        }

        let legacyIndividual = defaults.object(forKey: Keys.notifyOnSessionCompletion) as? Bool ?? false
        let legacyAllIdle = defaults.object(forKey: Keys.notifyOnCompletion) as? Bool ?? false

        if legacyIndividual {
            return .individual
        }
        if legacyAllIdle {
            return .allAgentsIdle
        }
        return .off
    }

    static var defaultStatusFilePath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.agent-traffic-lights/status.json"
    }
}
