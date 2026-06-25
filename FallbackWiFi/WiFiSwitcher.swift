import Foundation

@MainActor
final class WiFiSwitcher: ObservableObject {
    enum State: Equatable {
        case idle
        case checking
        case primaryOnline(String?)
        case fallbackActive(String)
        case switching(String)
        case noBackupSelected
        case disconnected
        case connectionPoor(String)
        case error(String)

        var title: String {
            switch self {
            case .idle:
                "Idle"
            case .checking:
                "Checking connection"
            case .primaryOnline(let ssid):
                ssid.map { "Connected to \($0)" } ?? "Connected"
            case .fallbackActive(let ssid):
                "Fallback active: \(ssid)"
            case .switching(let ssid):
                "Switching to \(ssid)"
            case .noBackupSelected:
                "No backup Wi-Fi selected"
            case .disconnected:
                "Disconnected"
            case .connectionPoor(let summary):
                "Connection poor: \(summary)"
            case .error(let message):
                "Error: \(message)"
            }
        }

        var isFallbackActive: Bool {
            if case .fallbackActive = self { return true }
            return false
        }
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var currentSSID: String?
    @Published private(set) var availableNetworks: [String] = []
    @Published private(set) var lastCheckedAt: Date?
    @Published private(set) var lastQuality: ConnectionQuality?

    private let settings: AppSettings
    private let wifiManager: WiFiManaging
    private let internetChecker: InternetChecking
    private let qualityChecker: ConnectionQualityChecking
    private let postJoinValidationDelayNanoseconds: UInt64
    private var timer: Timer?
    private var isChecking = false
    private var lastConnectedFallbackSSID: String?

    init(
        settings: AppSettings,
        wifiManager: WiFiManaging,
        internetChecker: InternetChecking,
        qualityChecker: ConnectionQualityChecking = HTTPConnectionQualityChecker(),
        postJoinValidationDelayNanoseconds: UInt64 = 2_000_000_000
    ) {
        self.settings = settings
        self.wifiManager = wifiManager
        self.internetChecker = internetChecker
        self.qualityChecker = qualityChecker
        self.postJoinValidationDelayNanoseconds = postJoinValidationDelayNanoseconds
    }

    func start() {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: settings.checkInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.checkNow(allowSwitch: true)
            }
        }
    }

    func restartTimer() {
        start()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refreshAvailableNetworks() async {
        do {
            availableNetworks = try await wifiManager.preferredNetworks()
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    func measureCurrentQuality() async {
        state = .checking
        lastQuality = await qualityChecker.measure()
        if let currentSSID, settings.backupSSIDs.contains(currentSSID) {
            state = .fallbackActive(currentSSID)
        } else {
            state = .primaryOnline(currentSSID)
        }
    }

    func checkNow(allowSwitch: Bool) async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        lastCheckedAt = Date()
        state = .checking

        let backups = settings.backupSSIDs
        NSLog("FallbackWiFi check started. backups=\(backups.isEmpty ? "none" : backups.joined(separator: ", ")), allowSwitch=\(allowSwitch), autoSwitch=\(settings.autoSwitchEnabled)")

        guard !backups.isEmpty else {
            state = .noBackupSelected
            currentSSID = nil
            NSLog("FallbackWiFi check stopped: no backup selected")
            return
        }

        do {
            var ssid = try await wifiManager.currentNetwork()
            if ssid == nil {
                ssid = await inferredFallbackSSIDWhenReadbackFails(backups: backups)
            }

            currentSSID = ssid
            NSLog("FallbackWiFi current SSID: \(ssid ?? "none")")

            let hasInternet = await internetChecker.hasInternetAccess()
            NSLog("FallbackWiFi internet access: \(hasInternet)")

            let poorQuality = hasInternet ? await poorQualityIfNeeded() : nil
            if let poorQuality {
                NSLog("FallbackWiFi quality is poor: \(poorQuality.summary)")
                guard settings.autoSwitchEnabled, allowSwitch else {
                    state = .connectionPoor(poorQuality.summary)
                    return
                }
            } else if hasInternet {
                if let ssid, backups.contains(ssid) {
                    lastConnectedFallbackSSID = ssid
                    state = .fallbackActive(ssid)
                    NSLog("FallbackWiFi backup already active")
                    return
                }

                lastConnectedFallbackSSID = nil
                state = .primaryOnline(ssid)
                return
            }

            guard settings.autoSwitchEnabled, allowSwitch else {
                state = ssid == nil ? .disconnected : .error("No internet access")
                NSLog("FallbackWiFi not switching: autoSwitch=\(settings.autoSwitchEnabled), allowSwitch=\(allowSwitch)")
                return
            }

            let candidates = await nearbySwitchCandidates(from: switchCandidates(from: backups, currentSSID: ssid))
            try await switchToFirstWorkingBackup(candidates)
        } catch {
            state = .error(error.localizedDescription)
            NSLog("FallbackWiFi check failed: \(error.localizedDescription)")
        }
    }

    private func inferredFallbackSSIDWhenReadbackFails(backups: [String]) async -> String? {
        if let lastConnectedFallbackSSID, backups.contains(lastConnectedFallbackSSID) {
            NSLog("FallbackWiFi inferred current backup from last successful switch: \(lastConnectedFallbackSSID)")
            return lastConnectedFallbackSSID
        }

        guard await wifiManager.isLikelyPersonalHotspotConnection() else {
            return nil
        }

        let hotspotBackups = backups.filter { backup in
            let lowercased = backup.localizedLowercase
            return lowercased.contains("iphone") || lowercased.contains("hotspot")
        }
        let inferred = hotspotBackups.count == 1 ? hotspotBackups[0] : backups.count == 1 ? backups[0] : nil
        guard let inferred else { return nil }

        NSLog("FallbackWiFi inferred current backup from constrained hotspot interface: \(inferred)")
        return inferred
    }

    private func poorQualityIfNeeded() async -> ConnectionQuality? {
        guard settings.qualitySwitchEnabled else { return nil }

        let quality = await qualityChecker.measure()
        lastQuality = quality
        return quality.isPoor(
            maximumLatencyMs: settings.maximumLatencyMs,
            minimumDownloadMbps: settings.minimumDownloadMbps
        ) ? quality : nil
    }

    private func switchCandidates(from backups: [String], currentSSID: String?) -> [String] {
        guard let currentSSID, let currentIndex = backups.firstIndex(of: currentSSID) else {
            return backups
        }

        let laterBackups = backups.dropFirst(currentIndex + 1)
        return laterBackups.isEmpty ? backups.filter { $0 != currentSSID } : Array(laterBackups)
    }

    private func nearbySwitchCandidates(from candidates: [String]) async -> [String] {
        guard !candidates.isEmpty else { return [] }

        do {
            let visibleNetworks = Set(try await wifiManager.visibleNetworks())
            let nearby = candidates.filter { visibleNetworks.contains($0) }

            if nearby.isEmpty {
                NSLog("FallbackWiFi no backup Wi-Fi is nearby. candidates=\(candidates.joined(separator: ", "))")
            } else if nearby != candidates {
                let skipped = candidates.filter { !nearby.contains($0) }
                NSLog("FallbackWiFi skipping non-nearby backups: \(skipped.joined(separator: ", "))")
            }

            return nearby
        } catch {
            NSLog("FallbackWiFi visible network scan failed, keeping backup candidates: \(error.localizedDescription)")
            return candidates
        }
    }

    private func switchToFirstWorkingBackup(_ candidates: [String]) async throws {
        guard !candidates.isEmpty else {
            throw WiFiError.commandFailed("No backup Wi-Fi is nearby")
        }

        var lastError: Error?

        for candidate in candidates {
            state = .switching(candidate)
            NSLog("FallbackWiFi switching to backup: \(candidate)")

            do {
                try await wifiManager.connect(to: candidate)
                if postJoinValidationDelayNanoseconds > 0 {
                    try? await Task.sleep(nanoseconds: postJoinValidationDelayNanoseconds)
                }

                let hasInternet = await internetChecker.hasInternetAccess()
                guard hasInternet else {
                    NSLog("FallbackWiFi backup has no internet after join: \(candidate)")
                    continue
                }

                if let poorQuality = await poorQualityIfNeeded() {
                    NSLog("FallbackWiFi backup quality is poor for \(candidate): \(poorQuality.summary)")
                    continue
                }

                lastConnectedFallbackSSID = candidate
                currentSSID = candidate
                state = .fallbackActive(candidate)
                NSLog("FallbackWiFi switch complete: \(candidate)")
                return
            } catch {
                lastError = error
                NSLog("FallbackWiFi backup failed for \(candidate): \(error.localizedDescription)")
            }
        }

        if let lastError {
            throw lastError
        }

        throw WiFiError.commandFailed("No backup Wi-Fi worked")
    }
}
