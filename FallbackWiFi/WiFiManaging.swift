@preconcurrency import CoreWLAN
import Foundation

protocol WiFiManaging: Sendable {
    func preferredNetworks() async throws -> [String]
    func currentNetwork() async throws -> String?
    func connect(to ssid: String) async throws
}

enum WiFiError: LocalizedError {
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let message):
            message
        }
    }
}

struct SystemWiFiManager: WiFiManaging {
    private let networksetup = "/usr/sbin/networksetup"

    func preferredNetworks() async throws -> [String] {
        let interface = try await wifiInterface()
        let result = await ShellCommand.run(networksetup, ["-listpreferredwirelessnetworks", interface])
        guard result.exitCode == 0 else {
            throw WiFiError.commandFailed(result.standardError)
        }

        let preferred = WiFiParsing.preferredNetworks(from: result.standardOutput)
        let visible = await visibleNetworks()
        return Array(Set(preferred + visible)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func currentNetwork() async throws -> String? {
        let interface = try await wifiInterface()
        let result = await ShellCommand.run(networksetup, ["-getairportnetwork", interface])
        guard result.exitCode == 0 else {
            throw WiFiError.commandFailed(result.standardError)
        }
        return WiFiParsing.currentNetwork(from: result.standardOutput)
    }

    func connect(to ssid: String) async throws {
        guard let password = await keychainPassword(for: ssid) else {
            throw WiFiError.commandFailed("Save the password for \(ssid) in FallbackWiFi Settings before auto-switching.")
        }

        do {
            try await connectWithCoreWLAN(to: ssid, password: password)
            NSLog("FallbackWiFi joined \(ssid) with CoreWLAN")
            return
        } catch {
            NSLog("FallbackWiFi CoreWLAN join failed for \(ssid): \(error.localizedDescription)")
        }

        let interface = try await wifiInterface()
        let arguments = ["-setairportnetwork", interface, ssid, password]

        let result = await ShellCommand.run(networksetup, arguments)
        guard result.exitCode == 0 else {
            throw WiFiError.commandFailed(result.standardError.isEmpty ? "Failed to join \(ssid)" : result.standardError)
        }
        NSLog("FallbackWiFi joined \(ssid) with networksetup")
    }

    private func wifiInterface() async throws -> String {
        let result = await ShellCommand.run(networksetup, ["-listallhardwareports"])
        guard result.exitCode == 0 else {
            throw WiFiError.commandFailed(result.standardError)
        }

        if let interface = WiFiParsing.wifiInterface(from: result.standardOutput) {
            return interface
        }

        throw WiFiError.commandFailed("Wi-Fi interface not found")
    }

    private func visibleNetworks() async -> [String] {
        await Task.detached {
            guard let interface = CWWiFiClient.shared().interface() else { return [] }

            do {
                let networks = try interface.scanForNetworks(withName: nil)
                return networks.compactMap { network in
                    network.ssid?.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                .filter { !$0.isEmpty }
            } catch {
                return []
            }
        }.value
    }

    private func connectWithCoreWLAN(to ssid: String, password: String?) async throws {
        try await Task.detached {
            guard let interface = CWWiFiClient.shared().interface() else {
                throw WiFiError.commandFailed("CoreWLAN interface not found")
            }

            let networks = try interface.scanForNetworks(withName: ssid)
            guard let network = networks.max(by: { $0.rssiValue < $1.rssiValue }) else {
                throw WiFiError.commandFailed("\(ssid) is not visible")
            }

            try interface.associate(to: network, password: password)
        }.value
    }

    private func keychainPassword(for ssid: String) async -> String? {
        FallbackPasswordStore.password(for: ssid)
    }
}
