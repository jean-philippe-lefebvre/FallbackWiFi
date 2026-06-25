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
        window.styleMask = [.titled, .closable, .resizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 560, height: 620))
        window.minSize = NSSize(width: 540, height: 460)
        window.center()
        self.window = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var switcher: WiFiSwitcher
    @State private var selectedNetworkToAdd = ""
    @State private var passwordSSID = ""
    @State private var hotspotPassword = ""
    @State private var passwordIsSaved = false
    @State private var passwordMessage: String?

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 18) {
                Text("FallbackWiFi")
                    .font(.title2.weight(.semibold))

                backupsSection

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

                qualitySection

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

                    helperText("The menu bar icon stays monochrome during normal Wi-Fi use. This color appears only when the backup network is active.")
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    statusRow("Status", value: switcher.state.title, color: switcher.state.isFallbackActive ? Color(nsColor: settings.activeColor.nsColor) : .secondary)
                    statusRow("Current", value: switcher.currentSSID ?? "None", color: .secondary)
                    statusRow("Quality", value: switcher.lastQuality?.summary ?? "Not tested", color: .secondary)

                    if let lastCheckedAt = switcher.lastCheckedAt {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Last check")
                                .frame(width: 72, alignment: .leading)
                            Text(lastCheckedAt, style: .time)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(width: 560, height: 620, alignment: .topLeading)
        .onAppear {
            syncSelectionState()
            refreshPasswordState()
            Task { await switcher.refreshAvailableNetworks() }
        }
        .onChange(of: settings.backupSSIDs) { _, _ in
            syncSelectionState()
            hotspotPassword = ""
            passwordMessage = nil
            refreshPasswordState()
        }
        .onChange(of: passwordSSID) { _, _ in
            hotspotPassword = ""
            passwordMessage = nil
            refreshPasswordState()
        }
    }

    private var backupsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Backup priority")
                .font(.headline)

            HStack {
                Picker("Add Wi-Fi", selection: $selectedNetworkToAdd) {
                    Text("Select a network").tag("")
                    ForEach(networksAvailableToAdd, id: \.self) { network in
                        Text(network).tag(network)
                    }
                }
                .pickerStyle(.menu)

                Button("Add") {
                    addSelectedNetwork()
                }
                .disabled(selectedNetworkToAdd.isEmpty)

                Button("Refresh") {
                    Task { await switcher.refreshAvailableNetworks() }
                }
            }

            if settings.backupSSIDs.isEmpty {
                helperText("Add at least one backup Wi-Fi. FallbackWiFi tries them from top to bottom.")
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(settings.backupSSIDs.enumerated()), id: \.element) { index, ssid in
                        backupRow(index: index, ssid: ssid)
                    }
                }
            }

            helperText("When a switch is needed, the app tries backup 1 first, then backup 2, and continues until one has Internet.")

            VStack(alignment: .leading, spacing: 8) {
                Picker("Password for", selection: $passwordSSID) {
                    Text("Select a backup").tag("")
                    ForEach(settings.backupSSIDs, id: \.self) { ssid in
                        Text(ssid).tag(ssid)
                    }
                }
                .pickerStyle(.menu)

                SecureField("Hotspot password", text: $hotspotPassword)
                    .textFieldStyle(.roundedBorder)
                    .disabled(passwordSSID.isEmpty)

                HStack(spacing: 10) {
                    Button(passwordIsSaved ? "Update password" : "Save password") {
                        saveHotspotPassword()
                    }
                    .disabled(passwordSSID.isEmpty || hotspotPassword.isEmpty)

                    Button("Remove password") {
                        removeHotspotPassword()
                    }
                    .disabled(passwordSSID.isEmpty || !passwordIsSaved)

                    Text(passwordStatusTitle)
                        .font(.caption)
                        .foregroundStyle(passwordIsSaved ? Color.secondary : Color.orange)
                        .lineLimit(1)
                }

                helperText("Save each secured backup once so automatic switches do not need to ask macOS for the Wi-Fi password.")

                if let passwordMessage {
                    helperText(passwordMessage)
                }
            }
        }
    }

    private var qualitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Connection quality")
                .font(.headline)

            Toggle("Switch when connection quality is poor", isOn: $settings.qualitySwitchEnabled)

            Picker("Max ping", selection: $settings.maximumLatencyMs) {
                ForEach(AppSettings.maximumLatencyOptions, id: \.value) { option in
                    Text(option.label).tag(option.value)
                }
            }
            .pickerStyle(.segmented)

            Picker("Min download", selection: $settings.minimumDownloadMbps) {
                ForEach(AppSettings.minimumDownloadOptions, id: \.value) { option in
                    Text(option.label).tag(option.value)
                }
            }
            .pickerStyle(.segmented)

            HStack {
                Button("Test current quality") {
                    Task { await switcher.measureCurrentQuality() }
                }

                Text(switcher.lastQuality?.summary ?? "Not tested")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            helperText("The automatic quality check uses ping plus a small download sample. It only affects switching when this option is enabled.")
        }
    }

    private var networksAvailableToAdd: [String] {
        switcher.availableNetworks.filter { !settings.backupSSIDs.contains($0) }
    }

    private var passwordStatusTitle: String {
        guard !passwordSSID.isEmpty else { return "No backup selected" }
        return passwordIsSaved ? "Saved for \(passwordSSID)" : "Not saved"
    }

    private func backupRow(index: Int, ssid: String) -> some View {
        HStack(spacing: 8) {
            Text("\(index + 1).")
                .foregroundStyle(.secondary)
                .frame(width: 22, alignment: .leading)

            Text(ssid)
                .lineLimit(1)

            Spacer()

            let hasPassword = FallbackPasswordStore.hasPassword(for: ssid)

            Text(hasPassword ? "Password saved" : "No password")
                .font(.caption)
                .foregroundStyle(hasPassword ? Color.secondary : Color.orange)

            Button("Up") {
                settings.moveBackupUp(ssid)
            }
            .disabled(index == 0)

            Button("Down") {
                settings.moveBackupDown(ssid)
            }
            .disabled(index == settings.backupSSIDs.count - 1)

            Button("Remove") {
                settings.removeBackup(ssid)
                if passwordSSID == ssid {
                    passwordSSID = settings.primaryBackupSSID ?? ""
                }
            }
        }
    }

    private func helperText(_ value: String) -> some View {
        Text(value)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func statusRow(_ label: String, value: String, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .foregroundStyle(color)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func syncSelectionState() {
        if selectedNetworkToAdd.isEmpty || !networksAvailableToAdd.contains(selectedNetworkToAdd) {
            selectedNetworkToAdd = networksAvailableToAdd.first ?? ""
        }

        if passwordSSID.isEmpty || !settings.backupSSIDs.contains(passwordSSID) {
            passwordSSID = settings.primaryBackupSSID ?? ""
        }
    }

    private func addSelectedNetwork() {
        settings.addBackup(selectedNetworkToAdd)
        selectedNetworkToAdd = networksAvailableToAdd.first ?? ""
        syncSelectionState()
    }

    private func refreshPasswordState() {
        passwordIsSaved = !passwordSSID.isEmpty && FallbackPasswordStore.hasPassword(for: passwordSSID)
    }

    private func saveHotspotPassword() {
        do {
            try FallbackPasswordStore.save(hotspotPassword, for: passwordSSID)
            hotspotPassword = ""
            passwordMessage = "Password saved in Keychain."
            refreshPasswordState()
        } catch {
            passwordMessage = error.localizedDescription
        }
    }

    private func removeHotspotPassword() {
        FallbackPasswordStore.deletePassword(for: passwordSSID)
        hotspotPassword = ""
        passwordMessage = "Password removed."
        refreshPasswordState()
    }
}
