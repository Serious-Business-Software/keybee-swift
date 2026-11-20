import Foundation
import Security

/// Keeps the licence in one Keychain generic-password item (account
/// "license"). Never synced: a grant is bound to this device.
struct KeychainStore: LicenseStore {
    let service: String
    let dataProtection: Bool

    init(service: String, dataProtection: Bool) {
        self.service = service
        self.dataProtection = dataProtection
    }

    private var baseQuery: [CFString: Any] {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: "license",
        ]
        if dataProtection { query[kSecUseDataProtectionKeychain] = true }
        return query
    }

    func read() -> StoreRead {
        var query = baseQuery
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { return .corrupt }
            return decodeStored(data)
        case errSecItemNotFound:
            return .empty
        default:
            return .unavailable(status)
        }
    }

    func write(_ license: StoredLicense) throws(KeybeeError) {
        let data = encodeStored(license)
        let accessible = dataProtection ? kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly : kSecAttrAccessibleAfterFirstUnlock
        var add = baseQuery
        add[kSecValueData] = data
        add[kSecAttrAccessible] = accessible
        var status = SecItemAdd(add as CFDictionary, nil)
        if status == errSecDuplicateItem {
            status = SecItemUpdate(baseQuery as CFDictionary, [kSecValueData: data] as CFDictionary)
        }
        guard status == errSecSuccess else { throw .storage(status) }
    }

    func delete() throws(KeybeeError) {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw .storage(status) }
    }
}
