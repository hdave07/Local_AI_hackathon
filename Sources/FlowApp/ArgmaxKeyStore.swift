import Foundation
import Security

/// Where Flow.app finds the Argmax runtime key: the `ARGMAX_API_KEY` environment variable
/// if set, otherwise the user's login Keychain. The key is never logged, shown or written
/// to the repository.
enum ArgmaxKeyStore {
    static let service = "dev.flow.FlowApp"
    static let account = "ARGMAX_API_KEY"

    enum Source: Equatable { case environment, keychain, none }

    static func load() -> (key: String?, source: Source) {
        if let env = ProcessInfo.processInfo.environment[account]?.trimmingCharacters(in: .whitespacesAndNewlines), !env.isEmpty {
            return (env, .environment)
        }
        var item: CFTypeRef?
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data,
              let key = String(data: data, encoding: .utf8), !key.isEmpty
        else { return (nil, .none) }
        return (key, .keychain)
    }

    /// Saves (or replaces) the key in the login Keychain. Returns an OSStatus description on failure.
    static func save(_ key: String) -> String? {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "The key is empty." }
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                   kSecAttrAccount as String: account]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = Data(trimmed.utf8)
        add[kSecAttrLabel as String] = "Flow – Argmax runtime key"
        let status = SecItemAdd(add as CFDictionary, nil)
        return status == errSecSuccess ? nil : (SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error \(status)")
    }
}
