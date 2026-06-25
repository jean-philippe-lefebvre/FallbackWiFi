import AppKit
import Combine

@MainActor
final class StatusBarController: NSObject {
    private let settings: AppSettings
    private let switcher: WiFiSwitcher
    private let statusItem: NSStatusItem
    private lazy var settingsWindowController = SettingsWindowController(settings: settings, switcher: switcher)
    private var cancellables = Set<AnyCancellable>()
    private var lastStableIconState: WiFiSwitcher.State = .idle

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

        settings.$backupColors
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

        let statusItem = NSMenuItem(title: shortMenuTitle(switcher.state.title), action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)

        let currentTitle = switcher.currentSSID.map { "Current: \(shortNetworkName($0))" } ?? "Current: none"
        let currentItem = NSMenuItem(title: currentTitle, action: nil, keyEquivalent: "")
        currentItem.isEnabled = false
        menu.addItem(currentItem)

        if let quality = switcher.lastQuality {
            let qualityItem = NSMenuItem(title: shortMenuTitle("Quality: \(quality.summary)"), action: nil, keyEquivalent: "")
            qualityItem.isEnabled = false
            menu.addItem(qualityItem)
        }

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

        let testItem = NSMenuItem(title: "Check Connection Now", action: #selector(checkNow), keyEquivalent: "")
        testItem.target = self
        menu.addItem(testItem)

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

    @objc private func checkNow() {
        Task { await switcher.checkNow(allowSwitch: true) }
    }

    @objc private func settingsAction() {
        settingsWindowController.show()
    }

    @objc private func quitAction() {
        NSApplication.shared.terminate(nil)
    }

    private func updateIcon() {
        guard let button = statusItem.button else { return }
        let iconState = stableIconState(for: switcher.state)
        button.image = FallbackIconRenderer.image(
            state: iconState,
            activeColor: activeIconColor(for: iconState)
        )
        button.toolTip = "FallbackWiFi: \(switcher.state.title)"
    }

    private func stableIconState(for state: WiFiSwitcher.State) -> WiFiSwitcher.State {
        if case .checking = state {
            return lastStableIconState
        }

        lastStableIconState = state
        return state
    }

    private func activeIconColor(for state: WiFiSwitcher.State) -> NSColor {
        if case .fallbackActive(let ssid) = state {
            return settings.color(for: ssid).nsColor
        }

        return settings.activeColor.nsColor
    }

    private func shortMenuTitle(_ title: String) -> String {
        if title.count <= 30 { return title }
        return String(title.prefix(27)) + "..."
    }

    private func shortNetworkName(_ name: String) -> String {
        if name.count <= 18 { return name }
        return String(name.prefix(15)) + "..."
    }
}
