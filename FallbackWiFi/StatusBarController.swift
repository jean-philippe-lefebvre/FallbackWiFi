import AppKit
import Combine

@MainActor
final class StatusBarController: NSObject {
    private let settings: AppSettings
    private let switcher: WiFiSwitcher
    private let statusItem: NSStatusItem
    private lazy var settingsWindowController = SettingsWindowController(settings: settings, switcher: switcher)
    private var cancellables = Set<AnyCancellable>()

    init(settings: AppSettings, switcher: WiFiSwitcher) {
        self.settings = settings
        self.switcher = switcher
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        setupButton()
        bindUpdates()
        updateIcon()
    }

    private func setupButton() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(handleClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.imagePosition = .imageOnly
    }

    private func bindUpdates() {
        switcher.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateIcon() }
            .store(in: &cancellables)

        settings.$activeColor
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateIcon() }
            .store(in: &cancellables)

        settings.$checkInterval
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.switcher.restartTimer() }
            .store(in: &cancellables)
    }

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        showContextMenu()
    }

    private func showContextMenu() {
        let menu = NSMenu()

        let statusItem = NSMenuItem(title: switcher.state.title, action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)

        let currentTitle = switcher.currentSSID.map { "Current: \($0)" } ?? "Current: none"
        let currentItem = NSMenuItem(title: currentTitle, action: nil, keyEquivalent: "")
        currentItem.isEnabled = false
        menu.addItem(currentItem)

        let backupTitle = settings.backupSSID.isEmpty ? "Backup: not selected" : "Backup: \(settings.backupSSID)"
        let backupItem = NSMenuItem(title: backupTitle, action: nil, keyEquivalent: "")
        backupItem.isEnabled = false
        menu.addItem(backupItem)

        let loginItem = NSMenuItem(title: LoginItemManager.statusTitle, action: nil, keyEquivalent: "")
        loginItem.isEnabled = false
        menu.addItem(loginItem)

        menu.addItem(.separator())

        let toggleItem = NSMenuItem(
            title: settings.autoSwitchEnabled ? "Disable Auto-Switch" : "Enable Auto-Switch",
            action: #selector(toggleAutoSwitch),
            keyEquivalent: ""
        )
        toggleItem.target = self
        menu.addItem(toggleItem)

        if LoginItemManager.canRegisterFromMenu {
            let loginAction = NSMenuItem(title: "Enable Launch at Login", action: #selector(enableLaunchAtLogin), keyEquivalent: "")
            loginAction.target = self
            menu.addItem(loginAction)
        }

        let testItem = NSMenuItem(title: "Test Now", action: #selector(testNow), keyEquivalent: "")
        testItem.target = self
        menu.addItem(testItem)

        let refreshNetworksItem = NSMenuItem(title: "Refresh Wi-Fi List", action: #selector(refreshNetworks), keyEquivalent: "")
        refreshNetworksItem.target = self
        menu.addItem(refreshNetworksItem)

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(settingsAction), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit FallbackWiFi", action: #selector(quitAction), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)

        self.statusItem.menu = menu
        self.statusItem.button?.performClick(nil)
        self.statusItem.menu = nil
    }

    @objc private func toggleAutoSwitch() {
        settings.autoSwitchEnabled.toggle()
    }

    @objc private func enableLaunchAtLogin() {
        settings.launchAtLoginEnabled = true
    }

    @objc private func testNow() {
        Task { await switcher.checkNow(allowSwitch: true) }
    }

    @objc private func refreshNetworks() {
        Task { await switcher.refreshAvailableNetworks() }
    }

    @objc private func settingsAction() {
        settingsWindowController.show()
    }

    @objc private func quitAction() {
        NSApplication.shared.terminate(nil)
    }

    private func updateIcon() {
        guard let button = statusItem.button else { return }
        button.image = FallbackIconRenderer.image(
            state: switcher.state,
            activeColor: settings.activeColor.nsColor
        )
        button.toolTip = "FallbackWiFi: \(switcher.state.title)"
    }
}
