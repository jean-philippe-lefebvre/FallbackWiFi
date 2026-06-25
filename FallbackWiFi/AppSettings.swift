import AppKit
import Foundation

@MainActor
final class AppSettings: ObservableObject {
    enum ActiveColor: String, CaseIterable, Identifiable {
        case green
        case blue
        case orange
        case red

        var id: String { rawValue }

        var title: String {
            switch self {
            case .green: "Green"
            case .blue: "Blue"
            case .orange: "Orange"
            case .red: "Red"
            }
        }

        var nsColor: NSColor {
            switch self {
            case .green: NSColor.systemGreen
            case .blue: NSColor.systemBlue
            case .orange: NSColor.systemOrange
            case .red: NSColor.systemRed
            }
        }
    }

    private enum Key {
        static let backupSSID = "backupSSID"
        static let backupSSIDs = "backupSSIDs"
        static let backupColors = "backupColors"
        static let autoSwitchEnabled = "autoSwitchEnabled"
        static let launchAtLoginEnabled = "launchAtLoginEnabled"
        static let activeColor = "activeColor"
        static let checkInterval = "checkInterval"
        static let qualitySwitchEnabled = "qualitySwitchEnabled"
        static let confirmQualityWithSpeedTest = "confirmQualityWithSpeedTest"
        static let maximumLatencyMs = "maximumLatencyMs"
        static let minimumDownloadMbps = "minimumDownloadMbps"
    }

    static let checkIntervalOptions: [(label: String, value: TimeInterval)] = [
        ("5 sec", 5),
        ("10 sec", 10),
        ("30 sec", 30),
        ("1 min", 60),
    ]

    static let maximumLatencyOptions: [(label: String, value: Double)] = [
        ("200 ms", 200),
        ("500 ms", 500),
        ("1 sec", 1_000),
        ("2 sec", 2_000),
    ]

    static let minimumDownloadOptions: [(label: String, value: Double)] = [
        ("1 Mbps", 1),
        ("2 Mbps", 2),
        ("5 Mbps", 5),
        ("10 Mbps", 10),
    ]

    private let defaults: UserDefaults

    @Published var backupSSIDs: [String] {
        didSet {
            let normalized = Self.normalizedNetworks(backupSSIDs)
            if backupSSIDs != normalized {
                backupSSIDs = normalized
                return
            }
            defaults.set(backupSSIDs, forKey: Key.backupSSIDs)
            defaults.set(primaryBackupSSID ?? "", forKey: Key.backupSSID)
        }
    }

    @Published var backupColors: [String: String] {
        didSet { defaults.set(backupColors, forKey: Key.backupColors) }
    }

    var backupSSID: String {
        get { primaryBackupSSID ?? "" }
        set { backupSSIDs = newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? [] : [newValue] }
    }

    var primaryBackupSSID: String? {
        backupSSIDs.first
    }

    @Published var autoSwitchEnabled: Bool {
        didSet { defaults.set(autoSwitchEnabled, forKey: Key.autoSwitchEnabled) }
    }

    @Published var launchAtLoginEnabled: Bool {
        didSet {
            defaults.set(launchAtLoginEnabled, forKey: Key.launchAtLoginEnabled)
            LoginItemManager.setEnabled(launchAtLoginEnabled)
        }
    }

    @Published var activeColor: ActiveColor {
        didSet { defaults.set(activeColor.rawValue, forKey: Key.activeColor) }
    }

    @Published var checkInterval: TimeInterval {
        didSet { defaults.set(Self.normalizedInterval(checkInterval), forKey: Key.checkInterval) }
    }

    @Published var qualitySwitchEnabled: Bool {
        didSet { defaults.set(qualitySwitchEnabled, forKey: Key.qualitySwitchEnabled) }
    }

    @Published var confirmQualityWithSpeedTest: Bool {
        didSet { defaults.set(confirmQualityWithSpeedTest, forKey: Key.confirmQualityWithSpeedTest) }
    }

    @Published var maximumLatencyMs: Double {
        didSet {
            let normalized = Self.normalizedOption(maximumLatencyMs, options: Self.maximumLatencyOptions)
            if maximumLatencyMs != normalized {
                maximumLatencyMs = normalized
                return
            }
            defaults.set(maximumLatencyMs, forKey: Key.maximumLatencyMs)
        }
    }

    @Published var minimumDownloadMbps: Double {
        didSet {
            let normalized = Self.normalizedOption(minimumDownloadMbps, options: Self.minimumDownloadOptions)
            if minimumDownloadMbps != normalized {
                minimumDownloadMbps = normalized
                return
            }
            defaults.set(minimumDownloadMbps, forKey: Key.minimumDownloadMbps)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.backupSSID: "",
            Key.backupSSIDs: [],
            Key.backupColors: [:],
            Key.autoSwitchEnabled: true,
            Key.launchAtLoginEnabled: true,
            Key.activeColor: ActiveColor.green.rawValue,
            Key.checkInterval: 10,
            Key.qualitySwitchEnabled: false,
            Key.confirmQualityWithSpeedTest: false,
            Key.maximumLatencyMs: 500,
            Key.minimumDownloadMbps: 2,
        ])

        let storedBackups = defaults.stringArray(forKey: Key.backupSSIDs) ?? []
        let legacyBackup = defaults.string(forKey: Key.backupSSID) ?? ""
        let activeColorValue = ActiveColor(rawValue: defaults.string(forKey: Key.activeColor) ?? "") ?? .green
        let migratedBackups = Self.normalizedNetworks(storedBackups.isEmpty && !legacyBackup.isEmpty ? [legacyBackup] : storedBackups)
        backupSSIDs = migratedBackups
        backupColors = Self.normalizedBackupColors(
            defaults.dictionary(forKey: Key.backupColors),
            backups: migratedBackups,
            defaultColor: activeColorValue
        )
        autoSwitchEnabled = defaults.bool(forKey: Key.autoSwitchEnabled)
        launchAtLoginEnabled = defaults.bool(forKey: Key.launchAtLoginEnabled)
        activeColor = activeColorValue
        checkInterval = Self.normalizedInterval(defaults.double(forKey: Key.checkInterval))
        qualitySwitchEnabled = defaults.bool(forKey: Key.qualitySwitchEnabled)
        confirmQualityWithSpeedTest = defaults.bool(forKey: Key.confirmQualityWithSpeedTest)
        maximumLatencyMs = Self.normalizedOption(defaults.double(forKey: Key.maximumLatencyMs), options: Self.maximumLatencyOptions)
        minimumDownloadMbps = Self.normalizedOption(defaults.double(forKey: Key.minimumDownloadMbps), options: Self.minimumDownloadOptions)

        defaults.set(backupSSIDs, forKey: Key.backupSSIDs)
        defaults.set(primaryBackupSSID ?? "", forKey: Key.backupSSID)
        defaults.set(backupColors, forKey: Key.backupColors)
    }

    func addBackup(_ ssid: String) {
        let trimmed = ssid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !backupSSIDs.contains(trimmed) else { return }
        backupSSIDs.append(trimmed)
        if backupColors[trimmed] == nil {
            setColor(activeColor, for: trimmed)
        }
    }

    func removeBackup(_ ssid: String) {
        backupSSIDs.removeAll { $0 == ssid }
        var colors = backupColors
        colors.removeValue(forKey: ssid)
        backupColors = colors
    }

    func moveBackupUp(_ ssid: String) {
        guard let index = backupSSIDs.firstIndex(of: ssid), index > 0 else { return }
        backupSSIDs.swapAt(index, index - 1)
    }

    func moveBackupDown(_ ssid: String) {
        guard let index = backupSSIDs.firstIndex(of: ssid), index < backupSSIDs.count - 1 else { return }
        backupSSIDs.swapAt(index, index + 1)
    }

    func color(for ssid: String) -> ActiveColor {
        ActiveColor(rawValue: backupColors[ssid] ?? "") ?? activeColor
    }

    func setColor(_ color: ActiveColor, for ssid: String) {
        guard backupSSIDs.contains(ssid) else { return }
        var colors = backupColors
        colors[ssid] = color.rawValue
        backupColors = colors
    }

    private static func normalizedInterval(_ value: TimeInterval) -> TimeInterval {
        let allowed = checkIntervalOptions.map(\.value)
        return allowed.contains(value) ? value : 10
    }

    private static func normalizedOption(_ value: Double, options: [(label: String, value: Double)]) -> Double {
        let allowed = options.map(\.value)
        return allowed.contains(value) ? value : options.first?.value ?? value
    }

    private static func normalizedNetworks(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !seen.contains(trimmed) else { return nil }
            seen.insert(trimmed)
            return trimmed
        }
    }

    private static func normalizedBackupColors(
        _ stored: [String: Any]?,
        backups: [String],
        defaultColor: ActiveColor
    ) -> [String: String] {
        var colors: [String: String] = [:]

        for backup in backups {
            if
                let rawValue = stored?[backup] as? String,
                ActiveColor(rawValue: rawValue) != nil
            {
                colors[backup] = rawValue
            } else {
                colors[backup] = defaultColor.rawValue
            }
        }

        return colors
    }
}
