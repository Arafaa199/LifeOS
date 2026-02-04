import Foundation
import Security
import os

private let logger = Logger(subsystem: "com.nexus.app", category: "keychain")

/// Secure storage for sensitive data using iOS Keychain
/// Uses kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly for security + background access
final class KeychainManager {
    static let shared = KeychainManager()

    private let service = "com.nexus.app"

    private init() {}

    // MARK: - API Key

    private let apiKeyAccount = "nexus-api-key"

    var apiKey: String? {
        get { read(account: apiKeyAccount) }
        set {
            if let value = newValue {
                save(value, account: apiKeyAccount)
            } else {
                delete(account: apiKeyAccount)
            }
        }
    }

    var hasAPIKey: Bool {
        apiKey != nil
    }

    // MARK: - Migration from UserDefaults

    /// Migrate API key from UserDefaults to Keychain (one-time)
    func migrateFromUserDefaultsIfNeeded() {
        let migrationKey = "keychain_migration_v1_complete"
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }

        if let legacyKey = UserDefaults.standard.string(forKey: "nexusAPIKey"), !legacyKey.isEmpty {
            logger.info("Migrating API key from UserDefaults to Keychain")
            apiKey = legacyKey
            UserDefaults.standard.removeObject(forKey: "nexusAPIKey")
        }

        UserDefaults.standard.set(true, forKey: migrationKey)
        logger.info("Keychain migration complete")
    }

    // MARK: - Generic Keychain Operations

    private func save(_ value: String, account: String) {
        guard let data = value.data(using: .utf8) else {
            logger.error("Failed to encode value for keychain")
            return
        }

        // Delete existing item first
        delete(account: account)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            logger.error("Keychain save failed: \(status)")
        } else {
            logger.debug("Keychain save succeeded for \(account)")
        }
    }

    private func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            if status != errSecItemNotFound {
                logger.debug("Keychain read status: \(status) for \(account)")
            }
            return nil
        }

        return value
    }

    private func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            logger.warning("Keychain delete status: \(status) for \(account)")
        }
    }

    /// Clear all keychain items for this app (for testing/reset)
    func clearAll() {
        delete(account: apiKeyAccount)
        logger.info("Keychain cleared")
    }
}
