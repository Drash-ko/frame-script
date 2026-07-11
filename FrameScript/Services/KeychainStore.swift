import Foundation
import Security
import OSLog

enum KeychainStore {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "FrameScript", category: "Keychain")
    /// API keys stay in the user's login Keychain and are never serialized into
    /// `.fscr` project files or sample data.
    static func saveAPIKey(_ key: String, account: String) throws {
        let data = Data(key.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "FrameScript",
            kSecAttrAccount as String: account
        ]
        let attributes = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            logger.error("Keychain update failed. Status: \(updateStatus, privacy: .private)")
            throw KeychainError.unhandledStatus(updateStatus)
        }

        var addAttributes = query
        addAttributes[kSecValueData as String] = data
        let status = SecItemAdd(addAttributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            logger.error("Keychain write failed. Status: \(status, privacy: .private)")
            throw KeychainError.unhandledStatus(status)
        }
    }

    static func readAPIKey(account: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "FrameScript",
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            logger.error("Keychain read failed. Status: \(status, privacy: .private)")
            throw KeychainError.unhandledStatus(status)
        }
        guard let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func deleteAPIKey(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "FrameScript",
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            logger.error("Keychain delete failed. Status: \(status, privacy: .private)")
            throw KeychainError.unhandledStatus(status)
        }
    }
}

enum KeychainError: Error {
    case unhandledStatus(OSStatus)
}
