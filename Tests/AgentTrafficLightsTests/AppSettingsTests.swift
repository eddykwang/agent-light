import XCTest
@testable import AgentTrafficLights

final class AppSettingsTests: XCTestCase {
    func testDefaultsUseVerticalOrientationAndHomeStatusPath() {
        let defaults = UserDefaults(suiteName: "AppSettingsTests.defaults")!
        defaults.removePersistentDomain(forName: "AppSettingsTests.defaults")

        let settings = AppSettings(defaults: defaults)

        XCTAssertEqual(settings.orientation, .vertical)
        XCTAssertTrue(settings.statusFilePath.hasSuffix(".agent-traffic-lights/status.json"))
        XCTAssertTrue(settings.notificationsEnabled)
        XCTAssertTrue(settings.alertsEnabled)
        XCTAssertTrue(settings.notifyOnAttention)
        XCTAssertEqual(settings.completionNotificationMode, .off)
        XCTAssertFalse(settings.notifyOnSessionCompletion)
        XCTAssertFalse(settings.notifyOnCompletion)
        XCTAssertFalse(settings.launchAtLogin)
        XCTAssertEqual(settings.claudeCodeStatusMode, .automatic)
        XCTAssertFalse(settings.hasCompletedOnboarding)
    }

    func testPersistsOrientationPathAlertsAndLaunchPreference() {
        let defaults = UserDefaults(suiteName: "AppSettingsTests.persist")!
        defaults.removePersistentDomain(forName: "AppSettingsTests.persist")

        let settings = AppSettings(defaults: defaults)
        settings.orientation = .horizontal
        settings.statusFilePath = "/tmp/status.json"
        settings.notificationsEnabled = false
        settings.notifyOnAttention = false
        settings.completionNotificationMode = .individual
        settings.launchAtLogin = true
        settings.claudeCodeStatusMode = .hooks
        settings.hasCompletedOnboarding = true

        let reloaded = AppSettings(defaults: defaults)

        XCTAssertEqual(reloaded.orientation, .horizontal)
        XCTAssertEqual(reloaded.statusFilePath, "/tmp/status.json")
        XCTAssertFalse(reloaded.notificationsEnabled)
        XCTAssertFalse(reloaded.alertsEnabled)
        XCTAssertFalse(reloaded.notifyOnAttention)
        XCTAssertEqual(reloaded.completionNotificationMode, .individual)
        XCTAssertTrue(reloaded.notifyOnSessionCompletion)
        XCTAssertFalse(reloaded.notifyOnCompletion)
        XCTAssertTrue(reloaded.launchAtLogin)
        XCTAssertEqual(reloaded.claudeCodeStatusMode, .hooks)
        XCTAssertTrue(reloaded.hasCompletedOnboarding)
    }

    func testLegacyAlertsEnabledStaysSyncedWithNotifyOnAttention() {
        let defaults = UserDefaults(suiteName: "AppSettingsTests.alertsSync")!
        defaults.removePersistentDomain(forName: "AppSettingsTests.alertsSync")

        let settings = AppSettings(defaults: defaults)
        settings.alertsEnabled = false
        XCTAssertFalse(settings.notifyOnAttention)

        settings.notifyOnAttention = true
        XCTAssertTrue(settings.alertsEnabled)
    }

    func testCompletionModeMigratesLegacyIndividualPreference() {
        let defaults = UserDefaults(suiteName: "AppSettingsTests.legacyIndividualCompletion")!
        defaults.removePersistentDomain(forName: "AppSettingsTests.legacyIndividualCompletion")
        defaults.set(true, forKey: "notifyOnSessionCompletion")
        defaults.set(true, forKey: "notifyOnCompletion")

        let settings = AppSettings(defaults: defaults)

        XCTAssertEqual(settings.completionNotificationMode, .individual)
        XCTAssertTrue(settings.notifyOnSessionCompletion)
        XCTAssertFalse(settings.notifyOnCompletion)
    }

    func testCompletionModeMigratesLegacyAllIdlePreference() {
        let defaults = UserDefaults(suiteName: "AppSettingsTests.legacyAllIdleCompletion")!
        defaults.removePersistentDomain(forName: "AppSettingsTests.legacyAllIdleCompletion")
        defaults.set(false, forKey: "notifyOnSessionCompletion")
        defaults.set(true, forKey: "notifyOnCompletion")

        let settings = AppSettings(defaults: defaults)

        XCTAssertEqual(settings.completionNotificationMode, .allAgentsIdle)
        XCTAssertFalse(settings.notifyOnSessionCompletion)
        XCTAssertTrue(settings.notifyOnCompletion)
    }
}
