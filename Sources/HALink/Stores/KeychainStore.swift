import Foundation
import Security

struct KeychainStore {
    // Retain the credential namespace used by earlier builds for one-time migration.
    private let service = "app.enfinity.Hestia"
    let file: URL
    private let legacyReader: ((String) throws -> String?)?
    private let legacyRemover: ((String) throws -> Void)?

    init(
        file: URL? = nil,
        legacyReader: ((String) throws -> String?)? = nil,
        legacyRemover: ((String) throws -> Void)? = nil
    ) {
        self.file = file ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Hestia/tokens.json")
        self.legacyReader = legacyReader
        self.legacyRemover = legacyRemover
    }

    func read(address: String) throws -> String? {
        var tokens = try loadTokens()
        if let token = tokens[address] {
            return token
        }
        let legacyToken: String?
        if let legacyReader {
            legacyToken = try legacyReader(address)
        } else {
            legacyToken = try readLegacyKeychain(address: address)
        }
        guard let legacyToken else { return nil }
        tokens[address] = legacyToken
        try writeTokens(tokens)
        return legacyToken
    }

    func save(_ token: String, address: String) throws {
        var tokens = try loadTokens()
        tokens[address] = token
        try writeTokens(tokens)
    }

    func remove(address: String) throws {
        var tokens = try loadTokens()
        if tokens.removeValue(forKey: address) != nil {
            if tokens.isEmpty {
                if FileManager.default.fileExists(atPath: file.path) {
                    try FileManager.default.removeItem(at: file)
                }
            } else {
                try writeTokens(tokens)
            }
        }
        if let legacyRemover {
            try? legacyRemover(address)
        } else {
            try? removeLegacyKeychain(address: address)
        }
    }

    private func loadTokens() throws -> [String: String] {
        guard FileManager.default.fileExists(atPath: file.path) else { return [:] }
        let data = try Data(contentsOf: file)
        return try JSONDecoder().decode([String: String].self, from: data)
    }

    private func writeTokens(_ tokens: [String: String]) throws {
        let directory = file.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(tokens)
        let temporary = directory.appending(path: ".\(file.lastPathComponent).\(UUID().uuidString).tmp")
        guard FileManager.default.createFile(
            atPath: temporary.path,
            contents: data,
            attributes: [.posixPermissions: 0o600]
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }
        do {
            _ = try FileManager.default.replaceItemAt(file, withItemAt: temporary)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }

    private func legacyQuery(_ address: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: address]
    }

    private func readLegacyKeychain(address: String) throws -> String? {
        var query = legacyQuery(address)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw Failure(status) }
        return String(data: data, encoding: .utf8)
    }

    private func removeLegacyKeychain(address: String) throws {
        let status = SecItemDelete(legacyQuery(address) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Failure(status) }
    }

    struct Failure: LocalizedError {
        let status: OSStatus
        init(_ status: OSStatus) { self.status = status }
        var errorDescription: String? { "无法从旧系统钥匙串迁移 Token（\(status)），请在连接设置中重新填写一次 Token。" }
    }
}
