import AppKit
import SwiftUI

@main
struct FallbackWiFiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var switcher: WiFiSwitcher?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let settings = AppSettings()
        let wifiManager = SystemWiFiManager()
        let internetChecker = HTTPInternetChecker()
        let switcher = WiFiSwitcher(
            settings: settings,
            wifiManager: wifiManager,
            internetChecker: internetChecker
        )

        LoginItemManager.setEnabled(settings.launchAtLoginEnabled)

        self.switcher = switcher
        statusBarController = StatusBarController(settings: settings, switcher: switcher)

        Task {
            await switcher.refreshAvailableNetworks()
            await switcher.checkNow(allowSwitch: false)
            switcher.start()
        }
    }
}
