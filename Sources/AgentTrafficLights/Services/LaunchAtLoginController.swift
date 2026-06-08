import Foundation
import ServiceManagement

enum LaunchAtLoginController {
    enum State {
        case enabled
        case requiresApproval
        case notRegistered
        case notFound
        case unknown
    }

    static var state: State {
        switch SMAppService.mainApp.status {
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notRegistered:
            return .notRegistered
        case .notFound:
            return .notFound
        @unknown default:
            return .unknown
        }
    }

    static var isEnabled: Bool {
        state == .enabled
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            if state == .notRegistered || state == .notFound || state == .unknown {
                try SMAppService.mainApp.register()
            }
        } else if state == .enabled || state == .requiresApproval {
            try SMAppService.mainApp.unregister()
        }
    }
}
