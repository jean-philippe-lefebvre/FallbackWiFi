import Foundation
import ServiceManagement

enum LoginItemManager {
    static func setEnabled(_ enabled: Bool) {
        if enabled {
            register()
        } else {
            unregister()
        }
    }

    static func register() {
        guard SMAppService.mainApp.status != .enabled else { return }

        do {
            try SMAppService.mainApp.register()
        } catch {
            NSLog("FallbackWiFi failed to register as a login item: \(error.localizedDescription)")
        }
    }

    static func unregister() {
        do {
            try SMAppService.mainApp.unregister()
        } catch {
            NSLog("FallbackWiFi failed to unregister as a login item: \(error.localizedDescription)")
        }
    }

    static var canRegisterFromMenu: Bool {
        switch SMAppService.mainApp.status {
        case .enabled:
            false
        case .notRegistered, .notFound, .requiresApproval:
            true
        @unknown default:
            true
        }
    }

    static var statusTitle: String {
        switch SMAppService.mainApp.status {
        case .enabled:
            "Launch at Login: Enabled"
        case .requiresApproval:
            "Launch at Login: Needs Approval"
        case .notRegistered:
            "Launch at Login: Disabled"
        case .notFound:
            "Launch at Login: Not Available"
        @unknown default:
            "Launch at Login: Unknown"
        }
    }
}
