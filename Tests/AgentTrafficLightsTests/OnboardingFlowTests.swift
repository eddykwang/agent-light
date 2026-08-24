import XCTest
@testable import AgentTrafficLights

final class OnboardingFlowTests: XCTestCase {
    func testStepOrderMovesForwardAndBackward() {
        XCTAssertEqual(OnboardingStep.welcome.next, .signal)
        XCTAssertEqual(OnboardingStep.signal.next, .agents)
        XCTAssertEqual(OnboardingStep.agents.next, .complete)
        XCTAssertNil(OnboardingStep.complete.next)

        XCTAssertNil(OnboardingStep.welcome.previous)
        XCTAssertEqual(OnboardingStep.signal.previous, .welcome)
        XCTAssertEqual(OnboardingStep.agents.previous, .signal)
        XCTAssertEqual(OnboardingStep.complete.previous, .agents)
    }

    func testHookOutcomeResolutionUsesHooksOnlyAfterInstall() {
        let installed = ClaudeCodeHookChoiceResolution.resolve(.installed)
        XCTAssertEqual(installed.mode, .hooks)
        XCTAssertTrue(installed.hooksInstalled)
        XCTAssertTrue(installed.message.contains("Hooks are installed"))

        let declined = ClaudeCodeHookChoiceResolution.resolve(.declined)
        XCTAssertEqual(declined.mode, .automatic)
        XCTAssertFalse(declined.hooksInstalled)
        XCTAssertTrue(declined.message.contains("Transcript mode selected"))

        let failed = ClaudeCodeHookChoiceResolution.resolve(.failed("Permission denied"))
        XCTAssertEqual(failed.mode, .automatic)
        XCTAssertFalse(failed.hooksInstalled)
        XCTAssertTrue(failed.message.contains("Permission denied"))
        XCTAssertTrue(failed.message.contains("~/.claude/settings.json"))
    }

    func testCopilotHookOutcomeResolutionReflectsInstallResult() {
        let installed = CopilotHookChoiceResolution.resolve(.installed)
        XCTAssertTrue(installed.hooksInstalled)
        XCTAssertTrue(installed.message.contains("installed"))

        let skipped = CopilotHookChoiceResolution.resolve(.skipped)
        XCTAssertFalse(skipped.hooksInstalled)
        XCTAssertTrue(skipped.message.contains("skipped"))

        let failed = CopilotHookChoiceResolution.resolve(.failed("Conflict"))
        XCTAssertFalse(failed.hooksInstalled)
        XCTAssertTrue(failed.message.contains("Conflict"))
    }
}
