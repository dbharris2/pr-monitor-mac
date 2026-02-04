import Foundation

/// Using UserDefaults for development. Switch to Keychain for production release.
enum Keychain {
    private static let tokenKey = "github-token"

    static func setToken(_ token: String) {
        UserDefaults.standard.set(token, forKey: tokenKey)
    }

    static func getToken() -> String? {
        UserDefaults.standard.string(forKey: tokenKey)
    }

    static func deleteToken() {
        UserDefaults.standard.removeObject(forKey: tokenKey)
    }
}
