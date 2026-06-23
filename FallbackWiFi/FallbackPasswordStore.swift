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

    static func password(for ssid: String) -> String? {
        var query = baseQuery(for: ssid)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            return nil
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
}
