import XCTest
import AgentTrafficLightsCore

final class AgentConfigurationPathsTests: XCTestCase {
    func testCustomProviderHomesAndEmptyFallback() {
        XCTAssertEqual(AgentConfigurationPaths.codexHome(environment: ["CODEX_HOME": " /tmp/codex-test "]).path, "/tmp/codex-test")
        XCTAssertEqual(AgentConfigurationPaths.claudeHome(environment: ["CLAUDE_CONFIG_DIR": "/tmp/claude-test"]).path, "/tmp/claude-test")
        XCTAssertEqual(AgentConfigurationPaths.codexHome(environment: ["CODEX_HOME": " "]), AgentConfigurationPaths.codexHome(environment: [:]))
        XCTAssertEqual(AgentConfigurationPaths.claudeHome(environment: [:]).lastPathComponent, ".claude")
        XCTAssertEqual(AgentConfigurationPaths.codexHome(environment: ["CODEX_HOME": "~/custom-codex"]).path,
                       FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("custom-codex").path)
    }
}
