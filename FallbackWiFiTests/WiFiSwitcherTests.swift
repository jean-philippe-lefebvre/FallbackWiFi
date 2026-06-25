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
                Self.quality(latencyMs: 900, jitterMs: 20, packetLossPercent: 0, downloadMbps: nil),
                Self.quality(latencyMs: 50, jitterMs: 5, packetLossPercent: 0, downloadMbps: nil),
            ]),
            postJoinValidationDelayNanoseconds: 0
        )

        await switcher.checkNow(allowSwitch: true)

        XCTAssertEqual(wifiManager.connectedSSID, "JP iPhone")
        XCTAssertEqual(switcher.state, .fallbackActive("JP iPhone"))
    }

    func testSpeedTestIsSkippedWhenLightQualityIsGood() async {
        let settings = makeSettings()
        settings.backupSSID = "JP iPhone"
        settings.autoSwitchEnabled = true
        settings.qualitySwitchEnabled = true
        settings.confirmQualityWithSpeedTest = true
        let qualityChecker = FakeQualityChecker(
            lightQualities: [
                Self.quality(latencyMs: 50, jitterMs: 4, packetLossPercent: 0, downloadMbps: nil),
            ],
            speedQualities: [
                Self.quality(latencyMs: nil, jitterMs: nil, packetLossPercent: nil, downloadMbps: 0.5),
            ]
        )
        let switcher = WiFiSwitcher(
            settings: settings,
            wifiManager: FakeWiFiManager(currentNetwork: "Home WiFi"),
            internetChecker: FakeInternetChecker(hasAccess: true),
            qualityChecker: qualityChecker,
            postJoinValidationDelayNanoseconds: 0
        )

        await switcher.checkNow(allowSwitch: true)

        XCTAssertEqual(qualityChecker.lightMeasureCount, 1)
        XCTAssertEqual(qualityChecker.speedMeasureCount, 0)
        XCTAssertEqual(switcher.state, .primaryOnline("Home WiFi"))
    }

    func testSpeedConfirmationCanPreventSwitchWhenDownloadIsHealthy() async {
        let settings = makeSettings()
        settings.backupSSID = "JP iPhone"
        settings.autoSwitchEnabled = true
        settings.qualitySwitchEnabled = true
        settings.confirmQualityWithSpeedTest = true
        settings.minimumDownloadMbps = 2
        let wifiManager = FakeWiFiManager(currentNetwork: "Home WiFi")
        let qualityChecker = FakeQualityChecker(
            lightQualities: [
                Self.quality(latencyMs: 900, jitterMs: 20, packetLossPercent: 0, downloadMbps: nil),
            ],
            speedQualities: [
                Self.quality(latencyMs: nil, jitterMs: nil, packetLossPercent: nil, downloadMbps: 20),
            ]
        )
        let switcher = WiFiSwitcher(
            settings: settings,
            wifiManager: wifiManager,
            internetChecker: FakeInternetChecker(hasAccess: true),
            qualityChecker: qualityChecker,
            postJoinValidationDelayNanoseconds: 0
        )

        await switcher.checkNow(allowSwitch: true)

        XCTAssertEqual(qualityChecker.lightMeasureCount, 1)
        XCTAssertEqual(qualityChecker.speedMeasureCount, 1)
        XCTAssertNil(wifiManager.connectedSSID)
        XCTAssertEqual(switcher.state, .primaryOnline("Home WiFi"))
    }

    private func makeSettings() -> AppSettings {
        let suiteName = "FallbackWiFiTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return AppSettings(defaults: defaults)
    }

    private static func quality(
        latencyMs: Double?,
        jitterMs: Double?,
        packetLossPercent: Double?,
        downloadMbps: Double?
    ) -> ConnectionQuality {
        ConnectionQuality(
            latencyMs: latencyMs,
            jitterMs: jitterMs,
            packetLossPercent: packetLossPercent,
            downloadMbps: downloadMbps,
            measuredAt: Date()
        )
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
    var lightQualities: [ConnectionQuality]
    var speedQualities: [ConnectionQuality]
    private(set) var lightMeasureCount = 0
    private(set) var speedMeasureCount = 0

    init(qualities: [ConnectionQuality]) {
        self.lightQualities = qualities
        self.speedQualities = qualities
    }

    init(lightQualities: [ConnectionQuality], speedQualities: [ConnectionQuality]) {
        self.lightQualities = lightQualities
        self.speedQualities = speedQualities
    }

    func measureLight() async -> ConnectionQuality {
        lightMeasureCount += 1
        if lightQualities.count > 1 {
            return lightQualities.removeFirst()
        }

        return lightQualities[0]
    }

    func measureSpeed() async -> ConnectionQuality {
        speedMeasureCount += 1
        if speedQualities.count > 1 {
            return speedQualities.removeFirst()
        }

        return speedQualities[0]
    }

    func measureFull() async -> ConnectionQuality {
        lightMeasureCount += 1
        speedMeasureCount += 1
        if lightQualities.count > 1 {
            return lightQualities.removeFirst().addingSpeed(from: speedQualities.removeFirst())
        }

        return lightQualities[0].addingSpeed(from: speedQualities[0])
    }
}
