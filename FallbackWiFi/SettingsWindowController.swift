import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private let settings: AppSettings
    private let switcher: WiFiSwitcher
    private var window: NSWindow?

    init(settings: AppSettings, switcher: WiFiSwitcher) {
        self.settings = settings
        self.switcher = switcher
    }

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let controller = NSHostingController(rootView: SettingsView(settings: settings, switcher: switcher))
        let window = NSWindow(contentViewController: controller)
        window.title = "FallbackWiFi Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 460, height: 430))
        window.center()
        self.window = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var switcher: WiFiSwitcher

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("FallbackWiFi")
                .font(.title2.weight(.semibold))

            VStack(alignment: .leading, spacing: 10) {
                Picker("Backup Wi-Fi", selection: $settings.backupSSID) {
                    Text("Select a backup").tag("")
                    ForEach(switcher.availableNetworks, id: \.self) { network in
                        Text(network).tag(network)
                    }
                }
                .pickerStyle(.menu)

                HStack {
                    Button("Refresh networks") {
                        Task { await switcher.refreshAvailableNetworks() }
                    }

                    Button("Test now") {
                        Task { await switcher.checkNow(allowSwitch: true) }
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Toggle("Launch at login", isOn: $settings.launchAtLoginEnabled)

                Toggle("Auto-switch when connection fails", isOn: $settings.autoSwitchEnabled)

                Picker("Check interval", selection: $settings.checkInterval) {
                    ForEach(AppSettings.checkIntervalOptions, id: \.value) { option in
                        Text(option.label).tag(option.value)
                    }
                }
                .pickerStyle(.segmented)
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("Fallback active color")
                    .font(.headline)

                Picker("Fallback active color", selection: $settings.activeColor) {
                    ForEach(AppSettings.ActiveColor.allCases) { color in
                        HStack {
                            Circle()
                                .fill(Color(nsColor: color.nsColor))
                                .frame(width: 10, height: 10)
                            Text(color.title)
                        }
                        .tag(color)
                    }
                }
                .pickerStyle(.segmented)

                Text("The menu bar icon stays monochrome during normal Wi-Fi use. This color appears only when the backup network is active.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                LabeledContent("Status") {
                    Text(switcher.state.title)
                        .foregroundStyle(switcher.state.isFallbackActive ? Color(nsColor: settings.activeColor.nsColor) : .secondary)
                }

                LabeledContent("Current") {
                    Text(switcher.currentSSID ?? "None")
                        .foregroundStyle(.secondary)
                }

                if let lastCheckedAt = switcher.lastCheckedAt {
                    LabeledContent("Last check") {
                        Text(lastCheckedAt, style: .time)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(22)
        .frame(width: 460, height: 430, alignment: .topLeading)
        .onAppear {
            Task { await switcher.refreshAvailableNetworks() }
        }
    }
}
