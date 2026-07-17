import Foundation
import Security

enum KeychainError: LocalizedError {
    case saveFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .saveFailed(let status):
            return "Keychain save failed with status \(status)."
        }
    }
}

enum KeychainStore {
    private static let service = "com.proxsyi.claudesessionpinger"
    private static let legacyServices = ["com.cash.claudesessionpinger"]
    private static let account = "sessionKey"

    static func save(_ value: String, account: String = KeychainStore.account) throws {
        try save(value, account: account, service: service)
    }

    private static func save(_ value: String, account: String, service: String) throws {
        let data = Data(value.utf8)
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(baseQuery as CFDictionary)
        var attributes = baseQuery
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    static func load(account: String = KeychainStore.account) -> String? {
        if let value = load(account: account, service: service) {
            return value
        }
        for legacyService in legacyServices {
            guard let value = load(account: account, service: legacyService) else { continue }
            do {
                try save(value, account: account, service: service)
                delete(account: account, service: legacyService)
            } catch {
                return value
            }
            return value
        }
        return nil
    }

    private static func load(account: String, service: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    static func delete(account: String = KeychainStore.account) {
        delete(account: account, service: service)
    }

    private static func delete(account: String, service: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
