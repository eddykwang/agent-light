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
        XCTAssertFalse(settings.desktopLightVisible)
        XCTAssertNil(settings.desktopLightPosition)
        XCTAssertEqual(settings.desktopLightScale, 1.0)
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
        settings.desktopLightVisible = true
        settings.desktopLightPosition = DesktopLightPosition(x: 412.5, y: 238.25)
        settings.desktopLightScale = 1.6

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
        XCTAssertTrue(reloaded.desktopLightVisible)
        XCTAssertEqual(reloaded.desktopLightPosition, DesktopLightPosition(x: 412.5, y: 238.25))
        XCTAssertEqual(reloaded.desktopLightScale, 1.6)
    }

    func testCanClearPersistedDesktopLightPosition() {
        let defaults = UserDefaults(suiteName: "AppSettingsTests.desktopLightPosition")!
        defaults.removePersistentDomain(forName: "AppSettingsTests.desktopLightPosition")

        let settings = AppSettings(defaults: defaults)
        settings.desktopLightPosition = DesktopLightPosition(x: 100, y: 200)
        settings.desktopLightPosition = nil

        let reloaded = AppSettings(defaults: defaults)
        XCTAssertNil(reloaded.desktopLightPosition)
    }

    func testDesktopLightScaleIsClampedWhenPersisted() {
        let defaults = UserDefaults(suiteName: "AppSettingsTests.desktopLightScale")!
        defaults.removePersistentDomain(forName: "AppSettingsTests.desktopLightScale")

        let settings = AppSettings(defaults: defaults)
        settings.desktopLightScale = 10
        XCTAssertEqual(settings.desktopLightScale, DesktopLightScaleLimits.maximum)

        settings.desktopLightScale = 0.1
        XCTAssertEqual(settings.desktopLightScale, DesktopLightScaleLimits.minimum)
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
