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
        window.setContentSize(NSSize(width: 560, height: 500))
        window.minSize = NSSize(width: 520, height: 420)
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
    @State private var selectedBackupSSID = ""
    @State private var hotspotPassword = ""
    @State private var passwordIsSaved = false
    @State private var passwordMessage: String?

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }

            backupsTab
                .tabItem { Label("Backups", systemImage: "wifi") }

            qualityTab
                .tabItem { Label("Quality", systemImage: "speedometer") }
        }
        .padding(20)
        .frame(width: 560, height: 500)
        .onAppear {
            syncSelectionState()
            refreshPasswordState()
            Task { await switcher.refreshAvailableNetworks() }
        }
        .onChange(of: switcher.availableNetworks) { _, _ in syncSelectionState() }
        .onChange(of: settings.backupSSIDs) { _, _ in
            syncSelectionState()
            resetPasswordEditor()
        }
        .onChange(of: selectedBackupSSID) { _, _ in resetPasswordEditor() }
    }

    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            header("FallbackWiFi", subtitle: "Automatic Wi-Fi fallback from the menu bar.")

            VStack(alignment: .leading, spacing: 8) {
                sectionTitle("Status")
                statusRow("State", value: switcher.state.title, color: statusColor)
                statusRow("Current", value: switcher.currentSSID ?? "None", color: .secondary)
                statusRow("Backups", value: "\(settings.backupSSIDs.count)", color: .secondary)

                if let lastCheckedAt = switcher.lastCheckedAt {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Last check")
                            .frame(width: 82, alignment: .leading)
                        Text(lastCheckedAt, style: .time)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("Automation")
                Toggle("Launch at login", isOn: $settings.launchAtLoginEnabled)
                Toggle("Auto-switch when connection fails", isOn: $settings.autoSwitchEnabled)

                Picker("Check interval", selection: $settings.checkInterval) {
                    ForEach(AppSettings.checkIntervalOptions, id: \.value) { option in
                        Text(option.label).tag(option.value)
                    }
                }
                .pickerStyle(.segmented)
            }

            Spacer()

            HStack {
                Button("Check now") {
                    Task { await switcher.checkNow(allowSwitch: true) }
                }
                .keyboardShortcut("r", modifiers: [.command])

                Button("Refresh networks") {
                    Task { await switcher.refreshAvailableNetworks() }
                }

                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var backupsTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            header("Backups", subtitle: "Priority is applied only to Wi-Fi networks visible nearby.")

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

                Spacer()
            }

            if settings.backupSSIDs.isEmpty {
                emptyState("No backup Wi-Fi configured.")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(settings.backupSSIDs.enumerated()), id: \.element) { index, ssid in
                            backupListRow(index: index, ssid: ssid)
                        }
                    }
                }
                .frame(minHeight: 92, maxHeight: 150)
            }

            Divider()

            if let selectedBackup {
                backupDetail(selectedBackup)
            } else {
                emptyState("Select a backup to edit its password, color, or priority.")
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var qualityTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            header("Connection Quality", subtitle: "Optional quality checks can trigger fallback before a full outage.")

            Toggle("Switch when connection quality is poor", isOn: $settings.qualitySwitchEnabled)

            VStack(alignment: .leading, spacing: 12) {
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
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                sectionTitle("Manual test")
                HStack {
                    Button("Test current quality") {
                        Task { await switcher.measureCurrentQuality() }
                    }

                    Text(switcher.lastQuality?.summary ?? "Not tested")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text("The download sample uses about 1 MB per test. Keep automatic quality switching off when you want to avoid cellular data use.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func backupListRow(index: Int, ssid: String) -> some View {
        Button {
            selectedBackupSSID = ssid
        } label: {
            HStack(spacing: 10) {
                Text("\(index + 1).")
                    .foregroundStyle(.secondary)
                    .frame(width: 24, alignment: .leading)

                Circle()
                    .fill(Color(nsColor: settings.color(for: ssid).nsColor))
                    .frame(width: 12, height: 12)

                VStack(alignment: .leading, spacing: 2) {
                    Text(ssid)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(FallbackPasswordStore.hasPassword(for: ssid) ? "Password saved" : "Password missing")
                        .font(.caption)
                        .foregroundStyle(FallbackPasswordStore.hasPassword(for: ssid) ? Color.secondary : Color.orange)
                }

                Spacer()
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(selectedBackupSSID == ssid ? Color.accentColor.opacity(0.16) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    private func backupDetail(_ ssid: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionTitle(ssid)
                Spacer()
                Button("Up") { settings.moveBackupUp(ssid) }
                    .disabled(settings.backupSSIDs.first == ssid)
                Button("Down") { settings.moveBackupDown(ssid) }
                    .disabled(settings.backupSSIDs.last == ssid)
                Button("Remove") { removeBackup(ssid) }
            }

            HStack(spacing: 8) {
                Text("Color")
                    .foregroundStyle(.secondary)
                    .frame(width: 72, alignment: .leading)
                colorSwatches(for: ssid)
            }

            SecureField("Wi-Fi password", text: $hotspotPassword)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button(passwordIsSaved ? "Update password" : "Save password") {
                    saveHotspotPassword()
                }
                .disabled(hotspotPassword.isEmpty)

                Button("Remove password") {
                    removeHotspotPassword()
                }
                .disabled(!passwordIsSaved)

                Text(passwordMessage ?? (passwordIsSaved ? "Password saved" : "No saved password"))
                    .font(.caption)
                    .foregroundStyle(passwordIsSaved ? Color.secondary : Color.orange)
                    .lineLimit(1)
            }
        }
    }

    private func colorSwatches(for ssid: String) -> some View {
        HStack(spacing: 8) {
            ForEach(AppSettings.ActiveColor.allCases) { color in
                Button {
                    settings.setColor(color, for: ssid)
                } label: {
                    Circle()
                        .fill(Color(nsColor: color.nsColor))
                        .frame(width: 18, height: 18)
                        .overlay(
                            Circle()
                                .stroke(settings.color(for: ssid) == color ? Color.primary : Color.clear, lineWidth: 2)
                        )
                        .padding(4)
                }
                .buttonStyle(.plain)
                .help("\(color.title) for \(ssid)")
            }
        }
    }

    private func header(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title2.weight(.semibold))
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.headline)
    }

    private func emptyState(_ value: String) -> some View {
        Text(value)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .center)
    }

    private func statusRow(_ label: String, value: String, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .frame(width: 82, alignment: .leading)
            Text(value)
                .foregroundStyle(color)
                .lineLimit(2)
        }
    }

    private var statusColor: Color {
        if case .fallbackActive(let ssid) = switcher.state {
            return Color(nsColor: settings.color(for: ssid).nsColor)
        }

        return .secondary
    }

    private var networksAvailableToAdd: [String] {
        switcher.availableNetworks.filter { !settings.backupSSIDs.contains($0) }
    }

    private var selectedBackup: String? {
        settings.backupSSIDs.contains(selectedBackupSSID) ? selectedBackupSSID : nil
    }

    private func syncSelectionState() {
        if selectedNetworkToAdd.isEmpty || !networksAvailableToAdd.contains(selectedNetworkToAdd) {
            selectedNetworkToAdd = networksAvailableToAdd.first ?? ""
        }

        if selectedBackupSSID.isEmpty || !settings.backupSSIDs.contains(selectedBackupSSID) {
            selectedBackupSSID = settings.primaryBackupSSID ?? ""
        }
    }

    private func addSelectedNetwork() {
        settings.addBackup(selectedNetworkToAdd)
        selectedBackupSSID = selectedNetworkToAdd
        selectedNetworkToAdd = networksAvailableToAdd.first ?? ""
        syncSelectionState()
    }

    private func removeBackup(_ ssid: String) {
        settings.removeBackup(ssid)
        if selectedBackupSSID == ssid {
            selectedBackupSSID = settings.primaryBackupSSID ?? ""
        }
    }

    private func resetPasswordEditor() {
        hotspotPassword = ""
        passwordMessage = nil
        refreshPasswordState()
    }

    private func refreshPasswordState() {
        passwordIsSaved = selectedBackup.map { FallbackPasswordStore.hasPassword(for: $0) } ?? false
    }

    private func saveHotspotPassword() {
        guard let selectedBackup else { return }

        do {
            try FallbackPasswordStore.save(hotspotPassword, for: selectedBackup)
            hotspotPassword = ""
            passwordMessage = "Saved"
            refreshPasswordState()
        } catch {
            passwordMessage = error.localizedDescription
        }
    }

    private func removeHotspotPassword() {
        guard let selectedBackup else { return }

        FallbackPasswordStore.deletePassword(for: selectedBackup)
        hotspotPassword = ""
        passwordMessage = "Removed"
        refreshPasswordState()
    }
}
