import Foundation
import Security

@MainActor
protocol APIKeyStore {
    /// Returns the stored key, or nil when none is saved.
    func readAPIKey() throws -> String?
    func saveAPIKey(_ key: String) throws
    /// Removing a missing key is not an error.
    func deleteAPIKey() throws
}

struct KeychainError: LocalizedError, Equatable {
    let operation: String
    let status: OSStatus

    var errorDescription: String? {
        let detail = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
        return "Keychain \(operation) failed: \(detail)"
    }
}

/// Generic-password Keychain storage for the Anthropic API key.
/// The key value must never be logged, exported, or shown back in the UI.
@MainActor
final class KeychainStore: APIKeyStore {
    private let service: String
    private let account = "anthropic-api-key"

    init(service: String = Bundle.main.bundleIdentifier ?? "dev.lsa.worder") {
        self.service = service
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    func readAPIKey() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data, let key = String(data: data, encoding: .utf8) else {
                throw KeychainError(operation: "decode", status: errSecDecode)
            }
            return key
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError(operation: "read", status: status)
        }
    }

    func saveAPIKey(_ key: String) throws {
        let data = Data(key.utf8)
        let attributes = [kSecValueData as String: data]

        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var addQuery = baseQuery
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError(operation: "add", status: addStatus)
            }
        default:
            throw KeychainError(operation: "update", status: updateStatus)
        }
    }

    func deleteAPIKey() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(operation: "delete", status: status)
        }
    }
}
