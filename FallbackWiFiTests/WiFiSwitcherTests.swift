import XCTest
@testable import FallbackWiFi

@MainActor
final class WiFiSwitcherTests: XCTestCase {
    func testCheckWithoutBackupDoesNotSwitch() async {
        let settings = makeSettings()
        settings.backupSSID = ""
        let wifiManager = FakeWiFiManager(currentNetwork: "Home WiFi")
        let switcher = WiFiSwitcher(
            settings: settings,
            wifiManager: wifiManager,
            internetChecker: FakeInternetChecker(hasAccess: false)
        )

        await switcher.checkNow(allowSwitch: true)

        XCTAssertEqual(switcher.state, .noBackupSelected)
        XCTAssertNil(wifiManager.connectedSSID)
    }

    func testFailedInternetSwitchesToBackupWhenAutoSwitchIsEnabled() async {
        let settings = makeSettings()
        settings.backupSSID = "JP iPhone"
        settings.autoSwitchEnabled = true
        let wifiManager = FakeWiFiManager(currentNetwork: "Home WiFi")
        let switcher = WiFiSwitcher(
            settings: settings,
            wifiManager: wifiManager,
            internetChecker: FakeInternetChecker(hasAccess: false)
        )

        await switcher.checkNow(allowSwitch: true)

        XCTAssertEqual(wifiManager.connectedSSID, "JP iPhone")
        XCTAssertEqual(switcher.state, .fallbackActive("JP iPhone"))
    }

    func testCurrentBackupNetworkIsReportedAsFallbackActive() async {
        let settings = makeSettings()
        settings.backupSSID = "JP iPhone"
        let wifiManager = FakeWiFiManager(currentNetwork: "JP iPhone")
        let switcher = WiFiSwitcher(
            settings: settings,
            wifiManager: wifiManager,
            internetChecker: FakeInternetChecker(hasAccess: true)
        )

        await switcher.checkNow(allowSwitch: true)

        XCTAssertEqual(switcher.state, .fallbackActive("JP iPhone"))
        XCTAssertNil(wifiManager.connectedSSID)
    }

    func testFallbackStateStaysActiveWhenSSIDReadbackIsUnavailable() async {
        let settings = makeSettings()
        settings.backupSSID = "JP iPhone"
        settings.autoSwitchEnabled = true
        let wifiManager = FakeWiFiManager(currentNetwork: "Home WiFi")
        let internetChecker = FakeInternetChecker(hasAccess: false)
        let switcher = WiFiSwitcher(
            settings: settings,
            wifiManager: wifiManager,
            internetChecker: internetChecker
        )

        await switcher.checkNow(allowSwitch: true)
        wifiManager.currentNetworkValue = nil
        wifiManager.connectedSSID = nil
        internetChecker.hasAccess = true

        await switcher.checkNow(allowSwitch: true)

        XCTAssertEqual(switcher.state, .fallbackActive("JP iPhone"))
    }

    private func makeSettings() -> AppSettings {
        let suiteName = "FallbackWiFiTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return AppSettings(defaults: defaults)
    }
}

private final class FakeWiFiManager: WiFiManaging, @unchecked Sendable {
    var connectedSSID: String?
    var currentNetworkValue: String?

    init(currentNetwork: String?) {
        self.currentNetworkValue = currentNetwork
    }

    func preferredNetworks() async throws -> [String] {
        ["Home WiFi", "JP iPhone"]
    }

    func currentNetwork() async throws -> String? {
        currentNetworkValue
    }

    func connect(to ssid: String) async throws {
        connectedSSID = ssid
    }
}

private final class FakeInternetChecker: InternetChecking, @unchecked Sendable {
    var hasAccess: Bool

    init(hasAccess: Bool) {
        self.hasAccess = hasAccess
    }

    func hasInternetAccess() async -> Bool {
        hasAccess
    }
}
