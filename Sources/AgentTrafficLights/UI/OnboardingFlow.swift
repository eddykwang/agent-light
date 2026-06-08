import Foundation

enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome
    case signal
    case claudeCode
    case complete

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .welcome:
            return "Welcome"
        case .signal:
            return "Signal"
        case .claudeCode:
            return "Claude Code"
        case .complete:
            return "Complete"
        }
    }

    var next: OnboardingStep? {
        guard let index = Self.allCases.firstIndex(of: self) else {
            return nil
        }

        let nextIndex = Self.allCases.index(after: index)
        return nextIndex < Self.allCases.endIndex ? Self.allCases[nextIndex] : nil
    }

    var previous: OnboardingStep? {
        guard let index = Self.allCases.firstIndex(of: self), index > Self.allCases.startIndex else {
            return nil
        }

        return Self.allCases[Self.allCases.index(before: index)]
    }
}

enum ClaudeCodeHookChoiceOutcome: Equatable {
    case installed
    case declined
    case failed(String)
}

struct ClaudeCodeHookChoiceResolution: Equatable {
    let mode: ClaudeCodeStatusMode
    let hooksInstalled: Bool
    let message: String

    static func resolve(_ outcome: ClaudeCodeHookChoiceOutcome) -> ClaudeCodeHookChoiceResolution {
        switch outcome {
        case .installed:
            return ClaudeCodeHookChoiceResolution(
                mode: .hooks,
                hooksInstalled: true,
                message: "Hooks are installed. Start a new Claude Code session for the most reliable status events."
            )
        case .declined:
            return ClaudeCodeHookChoiceResolution(
                mode: .automatic,
                hooksInstalled: false,
                message: "Transcript mode selected. You can install hooks later from Settings."
            )
        case .failed(let reason):
            return ClaudeCodeHookChoiceResolution(
                mode: .automatic,
                hooksInstalled: false,
                message: "Agent Light could not update ~/.claude/settings.json: \(reason)"
            )
        }
    }
}
