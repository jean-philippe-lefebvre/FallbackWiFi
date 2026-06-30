import Foundation

enum FallbackPasswordStore {
    private static let fileName = "backup-passwords.json"
    static var directoryOverride: URL?
    static var recoveryDirectoryOverride: URL?

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
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let passwords = try readPasswords(at: fileURL)
            try? saveRecoveryPasswords(passwords)
            return passwords
        }

        let recoveryURL = recoveryPasswordFileURL()
        guard FileManager.default.fileExists(atPath: recoveryURL.path) else { return [:] }

        let passwords = try readPasswords(at: recoveryURL)
        try? savePrimaryPasswords(passwords)
        return passwords
    }

    private static func readPasswords(at fileURL: URL) throws -> [String: String] {
        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else { return [:] }

        return try JSONDecoder().decode([String: String].self, from: data)
    }

    private static func savePasswords(_ passwords: [String: String]) throws {
        try savePrimaryPasswords(passwords)
        try saveRecoveryPasswords(passwords)
    }

    private static func savePrimaryPasswords(_ passwords: [String: String]) throws {
        try writePasswords(passwords, fileURL: passwordFileURL(), directoryURL: passwordDirectoryURL())
    }

    private static func saveRecoveryPasswords(_ passwords: [String: String]) throws {
        try writePasswords(passwords, fileURL: recoveryPasswordFileURL(), directoryURL: recoveryPasswordDirectoryURL())
    }

    private static func writePasswords(_ passwords: [String: String], fileURL: URL, directoryURL: URL) throws {
        try ensurePrivateDirectory(at: directoryURL)
        let data = try JSONEncoder().encode(passwords)
        try data.write(to: fileURL, options: [.atomic])
        try setPrivatePermissions(at: fileURL, mode: 0o600)
    }

    private static func passwordFileURL() -> URL {
        passwordDirectoryURL().appendingPathComponent(fileName)
    }

    private static func recoveryPasswordFileURL() -> URL {
        recoveryPasswordDirectoryURL().appendingPathComponent(fileName)
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

    private static func recoveryPasswordDirectoryURL() -> URL {
        if let recoveryDirectoryOverride {
            return recoveryDirectoryOverride
        }

        let libraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        return libraryURL
            .appendingPathComponent("Preferences", isDirectory: true)
            .appendingPathComponent("FallbackWiFi", isDirectory: true)
    }

    private static func ensurePrivateDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        try setPrivatePermissions(at: url, mode: 0o700)
    }

    private static func setPrivatePermissions(at url: URL, mode: Int) throws {
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path)
    }
}
