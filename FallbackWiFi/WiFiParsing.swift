import Foundation

enum WiFiParsing {
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
