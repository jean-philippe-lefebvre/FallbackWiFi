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
        window.setContentSize(NSSize(width: 640, height: 540))
        window.minSize = NSSize(width: 560, height: 460)
        window.center()
        self.window = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct SettingsView: View {
    private enum SettingsSection: String, CaseIterable, Identifiable {
        case general
        case backups
        case quality

        var id: String { rawValue }

        var title: String {
            switch self {
            case .general: "General"
            case .backups: "Backups"
            case .quality: "Quality"
            }
        }
    }

    @ObservedObject var settings: AppSettings
    @ObservedObject var switcher: WiFiSwitcher
    @State private var selectedSection: SettingsSection = .general
    @State private var selectedNetworkToAdd = ""
    @State private var selectedBackupSSID = ""
    @State private var hotspotPassword = ""
    @State private var passwordIsSaved = false
    @State private var passwordMessage: String?
    @State private var isTestingQuality = false

    var body: some View {
        VStack(spacing: 0) {
            settingsHeader

            ScrollView {
                activeSection
                    .padding(.horizontal, 32)
                    .padding(.top, 24)
                    .padding(.bottom, 28)
            }
        }
        .frame(width: 640, height: 540)
        .background(Color(nsColor: .windowBackgroundColor))
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

    private var settingsHeader: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 22) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("FallbackWiFi")
                        .font(.title2.weight(.semibold))

                    Text("Automatic Wi-Fi fallback from the menu bar.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 18)

                Picker("Settings section", selection: $selectedSection) {
                    ForEach(SettingsSection.allCases) { section in
                        Text(section.title).tag(section)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 318)
            }
            .padding(.horizontal, 32)
            .padding(.top, 28)

            Divider()
        }
    }

    @ViewBuilder
    private var activeSection: some View {
        switch selectedSection {
        case .general:
            generalTab
        case .backups:
            backupsTab
        case .quality:
            qualityTab
        }
    }

    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("Status")
                statusRow("State", value: switcher.state.title, color: statusColor)
                statusRow("Current", value: switcher.currentSSID ?? "None", color: .secondary)
                statusRow("Backups", value: "\(settings.backupSSIDs.count)", color: .secondary, tabular: true)

                if let lastCheckedAt = switcher.lastCheckedAt {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Last check")
                            .frame(width: 116, alignment: .leading)
                        Text(lastCheckedAt, style: .time)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 14) {
                sectionTitle("Automation")
                Toggle("Launch at login", isOn: $settings.launchAtLoginEnabled)
                Toggle("Auto-switch when connection fails", isOn: $settings.autoSwitchEnabled)

                Picker("Check interval", selection: $settings.checkInterval) {
                    ForEach(AppSettings.checkIntervalOptions, id: \.value) { option in
                        Text(option.label).tag(option.value)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 500)
            }

            Divider()

            HStack(spacing: 12) {
                Button("Check now") {
                    Task { await switcher.checkNow(allowSwitch: true) }
                }
                .keyboardShortcut("r", modifiers: [.command])
                .controlSize(.large)
                .frame(minHeight: 40)

                Button("Refresh networks") {
                    Task { await switcher.refreshAvailableNetworks() }
                }
                .controlSize(.large)
                .frame(minHeight: 40)

                Spacer()
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var backupsTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            contentHeader("Backups", subtitle: "Priority is applied only to Wi-Fi networks visible nearby.")

            HStack(spacing: 12) {
                Picker("Add Wi-Fi", selection: $selectedNetworkToAdd) {
                    Text("Select a network").tag("")
                    ForEach(networksAvailableToAdd, id: \.self) { network in
                        Text(network).tag(network)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 380)

                Button("Add") {
                    addSelectedNetwork()
                }
                .disabled(selectedNetworkToAdd.isEmpty)
                .controlSize(.large)
                .frame(minHeight: 40)

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
                .frame(minHeight: 120, maxHeight: 170)
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
        VStack(alignment: .leading, spacing: 22) {
            contentHeader("Connection Quality", subtitle: "Light monitoring watches ping, jitter, and packet loss before a full outage.")

            VStack(alignment: .leading, spacing: 10) {
                Toggle("Switch when connection quality is poor", isOn: $settings.qualitySwitchEnabled)
                Toggle("Run speed test only after degradation", isOn: $settings.confirmQualityWithSpeedTest)
                    .disabled(!settings.qualitySwitchEnabled)
                    .opacity(settings.qualitySwitchEnabled ? 1 : 0.6)
            }

            VStack(alignment: .leading, spacing: 14) {
                Picker("Max ping", selection: maximumLatencySelection) {
                    ForEach(AppSettings.maximumLatencyOptions, id: \.value) { option in
                        Text(option.label).tag(latencyTag(for: option.value))
                    }
                    Text("Custom").tag("custom")
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 500)

                if settings.maximumLatencyUsesCustom {
                    HStack(spacing: 10) {
                        Text("Custom ping")
                            .foregroundStyle(.secondary)
                            .frame(width: 116, alignment: .leading)
                        TextField("Max ping", value: $settings.maximumLatencyMs, format: .number.precision(.fractionLength(0)))
                            .textFieldStyle(.roundedBorder)
                            .monospacedDigit()
                            .frame(width: 96)
                        Text("ms")
                            .foregroundStyle(.secondary)
                    }
                }

                Picker("Min download", selection: $settings.minimumDownloadMbps) {
                    ForEach(AppSettings.minimumDownloadOptions, id: \.value) { option in
                        Text(option.label).tag(option.value)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 500)
                .disabled(!settings.confirmQualityWithSpeedTest)
                .opacity(settings.confirmQualityWithSpeedTest ? 1 : 0.6)
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("Manual test")
                HStack(spacing: 12) {
                    Button("Test current quality") {
                        runManualQualityTest()
                    }
                    .disabled(isTestingQuality)
                    .controlSize(.large)
                    .frame(minHeight: 40)

                    qualityTestStatus
                }
            }

            Text("Automatic checks use ping only by default. The 1 MB download sample runs only for manual tests or after degradation when speed confirmation is enabled.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func backupListRow(index: Int, ssid: String) -> some View {
        let hasPassword = FallbackPasswordStore.hasPassword(for: ssid)

        return Button {
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

                    Text(hasPassword ? "Password saved" : "Password missing")
                        .font(.caption)
                        .foregroundStyle(hasPassword ? Color.secondary : Color.orange)
                }

                Spacer()
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .frame(minHeight: 52)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(selectedBackupSSID == ssid ? Color.accentColor.opacity(0.16) : Color(nsColor: .controlBackgroundColor).opacity(0.45))
            )
        }
        .buttonStyle(.plain)
    }

    private func backupDetail(_ ssid: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                sectionTitle(ssid)
                Spacer()
                Button("Up") { settings.moveBackupUp(ssid) }
                    .disabled(settings.backupSSIDs.first == ssid)
                    .controlSize(.large)
                    .frame(minHeight: 40)
                Button("Down") { settings.moveBackupDown(ssid) }
                    .disabled(settings.backupSSIDs.last == ssid)
                    .controlSize(.large)
                    .frame(minHeight: 40)
                Button("Remove") { removeBackup(ssid) }
                    .controlSize(.large)
                    .frame(minHeight: 40)
            }

            HStack(spacing: 8) {
                Text("Color")
                    .foregroundStyle(.secondary)
                    .frame(width: 96, alignment: .leading)
                colorSwatches(for: ssid)
            }

            SecureField(passwordIsSaved ? "Password already saved" : "Wi-Fi password", text: $hotspotPassword)
                .textFieldStyle(.roundedBorder)
                .controlSize(.large)
                .disabled(passwordIsSaved)
                .opacity(passwordIsSaved ? 0.65 : 1)

            Text(passwordHelpText)
                .font(.caption)
                .foregroundStyle(passwordIsSaved ? Color.secondary : Color.orange)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Button("Save password") {
                    saveHotspotPassword()
                }
                .disabled(passwordIsSaved || hotspotPassword.isEmpty)
                .controlSize(.large)
                .frame(minHeight: 40)

                Button("Remove password") {
                    removeHotspotPassword()
                }
                .disabled(!passwordIsSaved)
                .controlSize(.large)
                .frame(minHeight: 40)

                Text(passwordMessage ?? (passwordIsSaved ? "Password saved" : "No saved password"))
                    .font(.caption)
                    .foregroundStyle(passwordIsSaved ? Color.secondary : Color.orange)
                    .lineLimit(2)
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
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
                .help("\(color.title) for \(ssid)")
            }
        }
    }

    private func contentHeader(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.title3.weight(.semibold))
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

    private func statusRow(_ label: String, value: String, color: Color, tabular: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .frame(width: 116, alignment: .leading)
            if tabular {
                Text(value)
                    .foregroundStyle(color)
                    .lineLimit(2)
                    .monospacedDigit()
            } else {
                Text(value)
                    .foregroundStyle(color)
                    .lineLimit(2)
            }
        }
    }

    private var maximumLatencySelection: Binding<String> {
        Binding(
            get: {
                settings.maximumLatencyUsesCustom ? "custom" : latencyTag(for: settings.maximumLatencyMs)
            },
            set: { tag in
                if tag == "custom" {
                    settings.maximumLatencyUsesCustom = true
                    return
                }

                guard let value = Double(tag) else { return }
                settings.maximumLatencyMs = value
                settings.maximumLatencyUsesCustom = false
            }
        )
    }

    private func latencyTag(for value: Double) -> String {
        String(Int(value.rounded()))
    }

    @ViewBuilder
    private var qualityTestStatus: some View {
        if isTestingQuality {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 16, height: 16)
                Text("Testing...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(minHeight: 24)
        } else {
            Text(switcher.lastQuality?.summary ?? "Not tested")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(2)
        }
    }

    private func runManualQualityTest() {
        guard !isTestingQuality else { return }
        isTestingQuality = true

        Task {
            await switcher.measureCurrentQuality()
            isTestingQuality = false
        }
    }

    private var passwordHelpText: String {
        if passwordIsSaved {
            return "Password saved for this backup. Remove it first before saving a different password."
        }

        return "Enter the Wi-Fi password once so automatic switches can join without asking macOS."
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
