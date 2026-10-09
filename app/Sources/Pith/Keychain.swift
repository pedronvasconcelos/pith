import Foundation
import Security

/// API keys live in the login keychain, never in defaults or on disk.
enum Keychain {
    private static let service = "app.pith"

    enum Account: String {
        case anthropic = "anthropic-api-key"
        case gemini = "gemini-api-key"
    }

    static var apiKey: String? {
        get { self[.anthropic] }
        set { self[.anthropic] = newValue }
    }

    static subscript(account: Account) -> String? {
        get {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account.rawValue,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
            ]
            var out: AnyObject?
            guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
                  let data = out as? Data, let key = String(data: data, encoding: .utf8), !key.isEmpty
            else { return nil }
            return key
        }
        set {
            let base: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account.rawValue,
            ]
            SecItemDelete(base as CFDictionary)
            guard let newValue, !newValue.isEmpty else { return }
            var add = base
            add[kSecValueData as String] = Data(newValue.utf8)
            SecItemAdd(add as CFDictionary, nil)
        }
    }
}
