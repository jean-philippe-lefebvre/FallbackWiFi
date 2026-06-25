import XCTest
@testable import FallbackWiFi

@MainActor
final class AppSettingsTests: XCTestCase {
    func testLegacyBackupInheritsActiveColor() {
        let suiteName = "FallbackWiFiTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set("JP iPhone", forKey: "backupSSID")
        defaults.set("orange", forKey: "activeColor")

        let settings = AppSettings(defaults: defaults)

        XCTAssertEqual(settings.backupSSIDs, ["JP iPhone"])
        XCTAssertEqual(settings.color(for: "JP iPhone"), .orange)
    }

    func testBackupColorCanDifferPerSSID() {
        let suiteName = "FallbackWiFiTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = AppSettings(defaults: defaults)

        settings.addBackup("JP iPhone")
        settings.addBackup("Office Hotspot")
        settings.setColor(.orange, for: "JP iPhone")
        settings.setColor(.blue, for: "Office Hotspot")

        XCTAssertEqual(settings.color(for: "JP iPhone"), .orange)
        XCTAssertEqual(settings.color(for: "Office Hotspot"), .blue)
    }

    func testSpeedConfirmationSettingPersists() {
        let suiteName = "FallbackWiFiTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = AppSettings(defaults: defaults)

        XCTAssertFalse(settings.confirmQualityWithSpeedTest)

        settings.confirmQualityWithSpeedTest = true
        let reloaded = AppSettings(defaults: defaults)

        XCTAssertTrue(reloaded.confirmQualityWithSpeedTest)
    }
}
