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
            internetChecker: FakeInternetChecker(hasAccess: false),
            postJoinValidationDelayNanoseconds: 0
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
        let internetChecker = FakeInternetChecker(hasAccess: false)
        wifiManager.onConnect = { _ in internetChecker.hasAccess = true }
        let switcher = WiFiSwitcher(
            settings: settings,
            wifiManager: wifiManager,
            internetChecker: internetChecker,
            postJoinValidationDelayNanoseconds: 0
        )

        await switcher.checkNow(allowSwitch: true)

        XCTAssertEqual(wifiManager.connectedSSID, "JP iPhone")
        XCTAssertEqual(switcher.state, .fallbackActive("JP iPhone"))
    }

    func testFailedBackupFallsThroughToNextPriority() async {
        let settings = makeSettings()
        settings.backupSSIDs = ["JP iPhone", "Office Hotspot"]
        settings.autoSwitchEnabled = true
        let wifiManager = FakeWiFiManager(currentNetwork: "Home WiFi")
        wifiManager.failedSSIDs = ["JP iPhone"]
        wifiManager.visibleNetworkValues = ["JP iPhone", "Office Hotspot"]
        let internetChecker = FakeInternetChecker(hasAccess: false)
        wifiManager.onConnect = { _ in internetChecker.hasAccess = true }
        let switcher = WiFiSwitcher(
            settings: settings,
            wifiManager: wifiManager,
            internetChecker: internetChecker,
            postJoinValidationDelayNanoseconds: 0
        )

        await switcher.checkNow(allowSwitch: true)

        XCTAssertEqual(wifiManager.connectionAttempts, ["JP iPhone", "Office Hotspot"])
        XCTAssertEqual(switcher.state, .fallbackActive("Office Hotspot"))
    }

    func testNonNearbyBackupIsSkippedBeforeConnectionAttempt() async {
        let settings = makeSettings()
        settings.backupSSIDs = ["Far Hotspot", "Office Hotspot"]
        settings.autoSwitchEnabled = true
        let wifiManager = FakeWiFiManager(currentNetwork: "Home WiFi")
        wifiManager.visibleNetworkValues = ["Office Hotspot"]
        let internetChecker = FakeInternetChecker(hasAccess: false)
        wifiManager.onConnect = { _ in internetChecker.hasAccess = true }
        let switcher = WiFiSwitcher(
            settings: settings,
            wifiManager: wifiManager,
            internetChecker: internetChecker,
            postJoinValidationDelayNanoseconds: 0
        )

        await switcher.checkNow(allowSwitch: true)

        XCTAssertEqual(wifiManager.connectionAttempts, ["Office Hotspot"])
        XCTAssertEqual(switcher.state, .fallbackActive("Office Hotspot"))
    }

    func testCurrentBackupNetworkIsReportedAsFallbackActive() async {
        let settings = makeSettings()
        settings.backupSSID = "JP iPhone"
        let wifiManager = FakeWiFiManager(currentNetwork: "JP iPhone")
        let switcher = WiFiSwitcher(
            settings: settings,
            wifiManager: wifiManager,
            internetChecker: FakeInternetChecker(hasAccess: true),
            postJoinValidationDelayNanoseconds: 0
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
        wifiManager.onConnect = { _ in internetChecker.hasAccess = true }
        let switcher = WiFiSwitcher(
            settings: settings,
            wifiManager: wifiManager,
            internetChecker: internetChecker,
            postJoinValidationDelayNanoseconds: 0
        )

        await switcher.checkNow(allowSwitch: true)
        wifiManager.currentNetworkValue = nil
        wifiManager.connectedSSID = nil
        internetChecker.hasAccess = true

        await switcher.checkNow(allowSwitch: true)

        XCTAssertEqual(switcher.state, .fallbackActive("JP iPhone"))
    }

    func testLikelyHotspotInfersIPhoneBackupWhenSSIDReadbackIsUnavailableOnLaunch() async {
        let settings = makeSettings()
        settings.backupSSIDs = ["Cafe WiFi", "JP iPhone"]
        let wifiManager = FakeWiFiManager(currentNetwork: nil)
        wifiManager.likelyPersonalHotspot = true
        let switcher = WiFiSwitcher(
            settings: settings,
            wifiManager: wifiManager,
            internetChecker: FakeInternetChecker(hasAccess: true),
            postJoinValidationDelayNanoseconds: 0
        )

        await switcher.checkNow(allowSwitch: false)

        XCTAssertEqual(switcher.state, .fallbackActive("JP iPhone"))
    }

    func testPoorQualityTriggersSwitchWhenEnabled() async {
        let settings = makeSettings()
        settings.backupSSID = "JP iPhone"
        settings.autoSwitchEnabled = true
        settings.qualitySwitchEnabled = true
        settings.maximumLatencyMs = 500
        settings.minimumDownloadMbps = 2
        let wifiManager = FakeWiFiManager(currentNetwork: "Home WiFi")
        let switcher = WiFiSwitcher(
            settings: settings,
            wifiManager: wifiManager,
            internetChecker: FakeInternetChecker(hasAccess: true),
            qualityChecker: FakeQualityChecker(qualities: [
                ConnectionQuality(latencyMs: 900, downloadMbps: 1, measuredAt: Date()),
                ConnectionQuality(latencyMs: 50, downloadMbps: 20, measuredAt: Date()),
            ]),
            postJoinValidationDelayNanoseconds: 0
        )

        await switcher.checkNow(allowSwitch: true)

        XCTAssertEqual(wifiManager.connectedSSID, "JP iPhone")
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
    var connectionAttempts: [String] = []
    var currentNetworkValue: String?
    var visibleNetworkValues = ["Home WiFi", "JP iPhone"]
    var failedSSIDs = Set<String>()
    var likelyPersonalHotspot = false
    var onConnect: ((String) -> Void)?

    init(currentNetwork: String?) {
        self.currentNetworkValue = currentNetwork
    }

    func preferredNetworks() async throws -> [String] {
        ["Home WiFi", "JP iPhone"]
    }

    func visibleNetworks() async throws -> [String] {
        visibleNetworkValues
    }

    func currentNetwork() async throws -> String? {
        currentNetworkValue
    }

    func connect(to ssid: String) async throws {
        connectionAttempts.append(ssid)
        if failedSSIDs.contains(ssid) {
            throw WiFiError.commandFailed("Failed to join \(ssid)")
        }

        connectedSSID = ssid
        currentNetworkValue = ssid
        onConnect?(ssid)
    }

    func isLikelyPersonalHotspotConnection() async -> Bool {
        likelyPersonalHotspot
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

private final class FakeQualityChecker: ConnectionQualityChecking, @unchecked Sendable {
    var qualities: [ConnectionQuality]

    init(qualities: [ConnectionQuality]) {
        self.qualities = qualities
    }

    func measure() async -> ConnectionQuality {
        if qualities.count > 1 {
            return qualities.removeFirst()
        }

        return qualities[0]
    }
}
