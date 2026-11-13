import Foundation
import Security

struct KeychainStore {
    // Retain the credential namespace used by the first build.
    private let service = "app.enfinity.Hestia"
    private func query(_ address: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: address]
    }
    func read(address: String) throws -> String? {
        var query = query(address)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw Failure(status) }
        return String(data: data, encoding: .utf8)
    }
    func save(_ token: String, address: String) throws {
        let data = Data(token.utf8)
        let status = SecItemUpdate(query(address) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query(address)
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw Failure(added) }
        } else if status != errSecSuccess { throw Failure(status) }
    }
    func remove(address: String) throws {
        let status = SecItemDelete(query(address) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Failure(status) }
    }
    struct Failure: LocalizedError {
        let status: OSStatus
        init(_ status: OSStatus) { self.status = status }
        var errorDescription: String? { "无法访问系统钥匙串（\(status)），请解锁登录钥匙串后重试。" }
    }
}
