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
        static let autoSwitchEnabled = "autoSwitchEnabled"
        static let launchAtLoginEnabled = "launchAtLoginEnabled"
        static let activeColor = "activeColor"
        static let checkInterval = "checkInterval"
    }

    static let checkIntervalOptions: [(label: String, value: TimeInterval)] = [
        ("5 sec", 5),
        ("10 sec", 10),
        ("30 sec", 30),
        ("1 min", 60),
    ]

    private let defaults: UserDefaults

    @Published var backupSSID: String {
        didSet { defaults.set(backupSSID, forKey: Key.backupSSID) }
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

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.backupSSID: "",
            Key.autoSwitchEnabled: true,
            Key.launchAtLoginEnabled: true,
            Key.activeColor: ActiveColor.green.rawValue,
            Key.checkInterval: 10,
        ])

        backupSSID = defaults.string(forKey: Key.backupSSID) ?? ""
        autoSwitchEnabled = defaults.bool(forKey: Key.autoSwitchEnabled)
        launchAtLoginEnabled = defaults.bool(forKey: Key.launchAtLoginEnabled)
        activeColor = ActiveColor(rawValue: defaults.string(forKey: Key.activeColor) ?? "") ?? .green
        checkInterval = Self.normalizedInterval(defaults.double(forKey: Key.checkInterval))
    }

    private static func normalizedInterval(_ value: TimeInterval) -> TimeInterval {
        let allowed = checkIntervalOptions.map(\.value)
        return allowed.contains(value) ? value : 10
    }
}
