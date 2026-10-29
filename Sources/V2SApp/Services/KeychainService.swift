import Foundation
import Security

/// Thin wrapper around the macOS Keychain for the small secrets v2s needs.
///
/// Secrets must never live in `settings.json` (a plain-text file) or in any
/// other file the app writes. Items are stored as generic passwords under
/// the app's own service name, without iCloud synchronization.
enum KeychainService {
    /// Account name for the AI translation API key.
    static let aiTranslationAPIKeyAccount = "ai-translation-api-key"

    private static let service = "v2s"

    @discardableResult
    static func save(_ value: String, forAccount account: String) -> Bool {
        guard let data = value.data(using: .utf8) else {
            return false
        }
        // The value data must be part of the add query: without it
        // SecItemAdd fails with errSecParam and nothing is stored, while
        // the caller only sees a silent false. The update query below
        // intentionally omits it, because it is a search query and must
        // match the existing item rather than the new value.
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status == errSecSuccess {
            return true
        }
        if status == errSecDuplicateItem {
            let matchQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
            ]
            let attributes: [String: Any] = [
                kSecValueData as String: data,
            ]
            return SecItemUpdate(matchQuery as CFDictionary, attributes as CFDictionary) == errSecSuccess
        }
        return false
    }

    static func load(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
