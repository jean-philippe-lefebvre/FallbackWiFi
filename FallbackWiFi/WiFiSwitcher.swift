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

    private let settings: AppSettings
    private let wifiManager: WiFiManaging
    private let internetChecker: InternetChecking
    private var timer: Timer?
    private var isChecking = false
    private var lastConnectedFallbackSSID: String?

    init(settings: AppSettings, wifiManager: WiFiManaging, internetChecker: InternetChecking) {
        self.settings = settings
        self.wifiManager = wifiManager
        self.internetChecker = internetChecker
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

    func checkNow(allowSwitch: Bool) async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        lastCheckedAt = Date()
        state = .checking

        let backupSSID = settings.backupSSID
        NSLog("FallbackWiFi check started. backup=\(backupSSID.isEmpty ? "none" : backupSSID), allowSwitch=\(allowSwitch), autoSwitch=\(settings.autoSwitchEnabled)")

        guard !backupSSID.isEmpty else {
            state = .noBackupSelected
            currentSSID = nil
            NSLog("FallbackWiFi check stopped: no backup selected")
            return
        }

        do {
            let ssid = try await wifiManager.currentNetwork()
            currentSSID = ssid
            NSLog("FallbackWiFi current SSID: \(ssid ?? "none")")

            if ssid == backupSSID {
                lastConnectedFallbackSSID = backupSSID
                state = .fallbackActive(backupSSID)
                NSLog("FallbackWiFi backup already active")
                return
            }

            let hasInternet = await internetChecker.hasInternetAccess()
            NSLog("FallbackWiFi internet access: \(hasInternet)")
            if hasInternet {
                if ssid == nil, lastConnectedFallbackSSID == backupSSID {
                    currentSSID = backupSSID
                    state = .fallbackActive(backupSSID)
                    NSLog("FallbackWiFi keeping fallback active after SSID readback disappeared")
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

            state = .switching(backupSSID)
            NSLog("FallbackWiFi switching to backup: \(backupSSID)")
            try await wifiManager.connect(to: backupSSID)
            lastConnectedFallbackSSID = backupSSID
            currentSSID = backupSSID
            state = .fallbackActive(backupSSID)
            NSLog("FallbackWiFi switch complete: \(backupSSID)")
        } catch {
            state = .error(error.localizedDescription)
            NSLog("FallbackWiFi check failed: \(error.localizedDescription)")
        }
    }
}
