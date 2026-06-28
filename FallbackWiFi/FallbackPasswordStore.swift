import Foundation

enum FallbackPasswordStore {
    private static let fileName = "backup-passwords.json"
    static var directoryOverride: URL?

    static func save(_ password: String, for ssid: String) throws {
        let trimmedSSID = ssid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSSID.isEmpty else { throw WiFiError.commandFailed("Select a backup Wi-Fi first") }

        var passwords = try loadPasswords()
        passwords[trimmedSSID] = password
        try savePasswords(passwords)
    }

    static func password(for ssid: String) throws -> String? {
        let passwords = try loadPasswords()
        return passwords[ssid]
    }

    static func hasPassword(for ssid: String) -> Bool {
        ((try? loadPasswords()) ?? [:])[ssid] != nil
    }

    static func deletePassword(for ssid: String) {
        guard var passwords = try? loadPasswords() else { return }
        passwords.removeValue(forKey: ssid)
        try? savePasswords(passwords)
    }

    private static func loadPasswords() throws -> [String: String] {
        let fileURL = passwordFileURL()
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return [:]
        }

        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else { return [:] }

        return try JSONDecoder().decode([String: String].self, from: data)
    }

    private static func savePasswords(_ passwords: [String: String]) throws {
        let directoryURL = passwordDirectoryURL()
        try ensurePrivateDirectory(at: directoryURL)

        let data = try JSONEncoder().encode(passwords)
        let fileURL = passwordFileURL()
        try data.write(to: fileURL, options: [.atomic])
        try setPrivatePermissions(at: fileURL, mode: 0o600)
    }

    private static func passwordFileURL() -> URL {
        passwordDirectoryURL().appendingPathComponent(fileName)
    }

    private static func passwordDirectoryURL() -> URL {
        if let directoryOverride {
            return directoryOverride
        }

        if let override = ProcessInfo.processInfo.environment["FALLBACKWIFI_PASSWORD_STORE_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }

        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return baseURL.appendingPathComponent("FallbackWiFi", isDirectory: true)
    }

    private static func ensurePrivateDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        try setPrivatePermissions(at: url, mode: 0o700)
    }

    private static func setPrivatePermissions(at url: URL, mode: Int) throws {
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path)
    }
}
