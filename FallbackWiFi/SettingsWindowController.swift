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
        window.setContentSize(NSSize(width: 500, height: 540))
        window.center()
        self.window = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var switcher: WiFiSwitcher
    @State private var hotspotPassword = ""
    @State private var passwordIsSaved = false
    @State private var passwordMessage: String?

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

                    Button("Check now") {
                        Task { await switcher.checkNow(allowSwitch: true) }
                    }
                }

                Text("Runs one connection check now. If Internet is down and auto-switch is enabled, it can switch to the backup Wi-Fi.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    SecureField("Hotspot password", text: $hotspotPassword)
                        .textFieldStyle(.roundedBorder)
                        .disabled(settings.backupSSID.isEmpty)

                    HStack(spacing: 10) {
                        Button(passwordIsSaved ? "Update password" : "Save password") {
                            saveHotspotPassword()
                        }
                        .disabled(settings.backupSSID.isEmpty || hotspotPassword.isEmpty)

                        Button("Remove") {
                            removeHotspotPassword()
                        }
                        .disabled(settings.backupSSID.isEmpty || !passwordIsSaved)

                        Text(passwordIsSaved ? "Saved for \(settings.backupSSID)" : "Not saved")
                            .font(.caption)
                            .foregroundStyle(passwordIsSaved ? Color.secondary : Color.orange)
                    }

                    Text("Save it once here so automatic switches do not need to ask macOS for the Wi-Fi password each time.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let passwordMessage {
                        Text(passwordMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
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

                HStack(spacing: 8) {
                    ForEach(AppSettings.ActiveColor.allCases) { color in
                        Button {
                            settings.activeColor = color
                        } label: {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Color(nsColor: color.nsColor))
                                    .frame(width: 10, height: 10)
                                    .overlay(
                                        Circle()
                                            .stroke(settings.activeColor == color ? Color.white.opacity(0.9) : Color.clear, lineWidth: 1)
                                    )

                                Text(color.title)
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .foregroundStyle(settings.activeColor == color ? .white : .primary)
                            .padding(.horizontal, 12)
                            .frame(height: 30)
                            .background(
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(settings.activeColor == color ? Color(nsColor: color.nsColor) : Color(nsColor: .controlBackgroundColor))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

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
        .frame(width: 500, height: 540, alignment: .topLeading)
        .onAppear {
            refreshPasswordState()
            Task { await switcher.refreshAvailableNetworks() }
        }
        .onChange(of: settings.backupSSID) { _, _ in
            hotspotPassword = ""
            passwordMessage = nil
            refreshPasswordState()
        }
    }

    private func refreshPasswordState() {
        passwordIsSaved = !settings.backupSSID.isEmpty && FallbackPasswordStore.hasPassword(for: settings.backupSSID)
    }

    private func saveHotspotPassword() {
        do {
            try FallbackPasswordStore.save(hotspotPassword, for: settings.backupSSID)
            hotspotPassword = ""
            passwordMessage = "Password saved in Keychain."
            refreshPasswordState()
        } catch {
            passwordMessage = error.localizedDescription
        }
    }

    private func removeHotspotPassword() {
        FallbackPasswordStore.deletePassword(for: settings.backupSSID)
        hotspotPassword = ""
        passwordMessage = "Password removed."
        refreshPasswordState()
    }
}
