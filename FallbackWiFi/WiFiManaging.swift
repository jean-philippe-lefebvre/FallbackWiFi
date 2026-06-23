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
    private let serviceName = "Wi-Fi"

    func preferredNetworks() async throws -> [String] {
        let result = await ShellCommand.run(networksetup, ["-listpreferredwirelessnetworks", serviceName])
        guard result.exitCode == 0 else {
            throw WiFiError.commandFailed(result.standardError)
        }
        return WiFiParsing.preferredNetworks(from: result.standardOutput)
    }

    func currentNetwork() async throws -> String? {
        let result = await ShellCommand.run(networksetup, ["-getairportnetwork", serviceName])
        guard result.exitCode == 0 else {
            throw WiFiError.commandFailed(result.standardError)
        }
        return WiFiParsing.currentNetwork(from: result.standardOutput)
    }

    func connect(to ssid: String) async throws {
        let result = await ShellCommand.run(networksetup, ["-setairportnetwork", serviceName, ssid])
        guard result.exitCode == 0 else {
            throw WiFiError.commandFailed(result.standardError)
        }
    }
}
