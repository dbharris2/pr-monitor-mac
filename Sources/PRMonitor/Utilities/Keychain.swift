import Foundation
import Security

enum Keychain {
    private static let service = "com.prmonitor.app"
    private static let account = "github-token"

    static func setToken(_ token: String) {
        // Delete any existing token first to avoid errSecDuplicateItem
        deleteToken()

        guard let data = token.data(using: .utf8) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecUseDataProtectionKeychain as String: true,
        ]

        SecItemAdd(query as CFDictionary, nil)
    }

    static func getToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseDataProtectionKeychain as String: true,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    static func deleteToken() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true,
        ]

        SecItemDelete(query as CFDictionary)
    }

    /// Migrates a token from UserDefaults to Keychain, then removes the UserDefaults entry.
    /// Safe to call multiple times — no-ops if there's nothing to migrate.
    static func migrateFromUserDefaultsIfNeeded() {
        let legacyKey = "github-token"
        guard let token = UserDefaults.standard.string(forKey: legacyKey) else { return }
        if getToken() == nil {
            setToken(token)
        }
        UserDefaults.standard.removeObject(forKey: legacyKey)
    }
}
