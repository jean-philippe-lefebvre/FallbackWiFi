import Foundation
import Security

enum FallbackPasswordStore {
    private static let service = "com.jplefebvre.fallbackwifi.backup-password"

    static func save(_ password: String, for ssid: String) throws {
        let trimmedSSID = ssid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSSID.isEmpty else { throw WiFiError.commandFailed("Select a backup Wi-Fi first") }

        let data = Data(password.utf8)
        let query = baseQuery(for: trimmedSSID)
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw WiFiError.commandFailed("Could not save password to Keychain (\(status))")
        }
    }

    static func password(for ssid: String) throws -> String? {
        var query = baseQuery(for: ssid)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess, let data = item as? Data else {
            throw WiFiError.commandFailed(readErrorMessage(for: ssid, status: status))
        }

        return String(data: data, encoding: .utf8)
    }

    static func hasPassword(for ssid: String) -> Bool {
        var query = baseQuery(for: ssid)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = false

        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    static func deletePassword(for ssid: String) {
        SecItemDelete(baseQuery(for: ssid) as CFDictionary)
    }

    private static func baseQuery(for ssid: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: ssid,
        ]
    }

    private static func readErrorMessage(for ssid: String, status: OSStatus) -> String {
        switch status {
        case errSecAuthFailed, errSecInteractionNotAllowed:
            return "Keychain access was denied for \(ssid). Choose Always Allow when macOS asks so FallbackWiFi can use the saved password."
        case errSecUserCanceled:
            return "Keychain access was cancelled for \(ssid). Choose Always Allow when macOS asks so automatic switching can use the saved password."
        default:
            return "Could not read the saved password for \(ssid) from Keychain (\(status))."
        }
    }
}
