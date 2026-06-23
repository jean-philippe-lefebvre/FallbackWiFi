import Foundation

enum WiFiParsing {
    static func wifiInterface(from hardwarePortsOutput: String) -> String? {
        let lines = hardwarePortsOutput.split(whereSeparator: \.isNewline).map(String.init)

        for index in lines.indices {
            guard lines[index].trimmingCharacters(in: .whitespacesAndNewlines) == "Hardware Port: Wi-Fi" else {
                continue
            }

            let deviceIndex = lines.index(after: index)
            guard lines.indices.contains(deviceIndex) else { return nil }

            let deviceLine = lines[deviceIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            let prefix = "Device:"
            guard deviceLine.hasPrefix(prefix) else { return nil }

            let device = deviceLine.dropFirst(prefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
            return device.isEmpty ? nil : device
        }

        return nil
    }

    static func preferredNetworks(from output: String) -> [String] {
        output
            .split(whereSeparator: \.isNewline)
            .dropFirst()
            .map { line in
                line.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
    }

    static func currentNetwork(from output: String) -> String? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let prefix = "Current Wi-Fi Network:"
        if trimmed.hasPrefix(prefix) {
            let name = trimmed.dropFirst(prefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? nil : name
        }

        if trimmed.localizedCaseInsensitiveContains("not associated") {
            return nil
        }

        return trimmed
    }
}
