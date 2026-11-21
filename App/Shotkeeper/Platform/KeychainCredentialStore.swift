import Foundation
import Security
import ShotkeeperCore

enum KeychainError: Error, Equatable {
    case status(operation: String, OSStatus)
    case invalidData

    /// True for statuses that mean "no usable keychain here" (locked/headless CI, missing entitlement),
    /// as opposed to a bug in our query.
    var isKeychainUnavailable: Bool {
        guard case .status(_, let status) = self else { return false }
        return [errSecInteractionNotAllowed, errSecNotAvailable, errSecNoSuchKeychain,
                errSecMissingEntitlement, errSecAuthFailed, errSecUserCanceled].contains(status)
    }
}

/// Secrets (e.g. the Cloudflare API token) as generic-password items: service = bundle id, account = `key.rawValue`.
/// Values are never logged; errors carry only the operation and OSStatus.
struct KeychainCredentialStore: CredentialStore {
    static let defaultService = "dev.shotkeeper.Shotkeeper"

    let service: String

    init(service: String = KeychainCredentialStore.defaultService) {
        self.service = service
    }

    func secret(for key: CredentialKey) throws -> String? {
        var query = baseQuery(key)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data, let string = String(data: data, encoding: .utf8) else {
                throw KeychainError.invalidData
            }
            return string
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.status(operation: "SecItemCopyMatching", status)
        }
    }

    func setSecret(_ value: String, for key: CredentialKey) throws {
        let data = Data(value.utf8)
        let update: [CFString: Any] = [kSecValueData: data, kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock]
        let updateStatus = SecItemUpdate(baseQuery(key) as CFDictionary, update as CFDictionary)
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var add = baseQuery(key)
            add[kSecValueData] = data
            add[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock
            add[kSecAttrLabel] = "Shotkeeper: \(key.rawValue)"
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.status(operation: "SecItemAdd", addStatus) }
        default:
            throw KeychainError.status(operation: "SecItemUpdate", updateStatus)
        }
    }

    func removeSecret(for key: CredentialKey) throws {
        let status = SecItemDelete(baseQuery(key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.status(operation: "SecItemDelete", status)
        }
    }

    private func baseQuery(_ key: CredentialKey) -> [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: key.rawValue]
    }
}
