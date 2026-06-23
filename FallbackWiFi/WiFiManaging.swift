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
        let interface = try await wifiInterface()
        let result = await ShellCommand.run(networksetup, ["-setairportnetwork", interface, ssid])
        guard result.exitCode == 0 else {
            throw WiFiError.commandFailed(result.standardError)
        }
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
}
