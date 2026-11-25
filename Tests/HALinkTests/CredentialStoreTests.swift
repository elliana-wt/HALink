import Foundation
import Testing
@testable import HALink

@Suite("本机 Token 存储与迁移")
struct CredentialStoreTests {
    @Test func savesReadsRemovesWithOwnerOnlyPermissions() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "HALink-tokens-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "tokens.json")
        var legacyReadCount = 0
        let store = KeychainStore(
            file: file,
            legacyReader: { _ in legacyReadCount += 1; return nil },
            legacyRemover: { _ in }
        )

        try store.save("secret-token-1", address: "http://ha.local:8123")
        #expect(try store.read(address: "http://ha.local:8123") == "secret-token-1")
        #expect(legacyReadCount == 0)

        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue
        #expect(permissions == 0o600)

        try store.save("secret-token-2", address: "http://ha2.local:8123")
        try store.remove(address: "http://ha.local:8123")
        #expect(try store.read(address: "http://ha2.local:8123") == "secret-token-2")
        #expect(try store.read(address: "http://ha.local:8123") == nil)
        #expect(legacyReadCount == 1)
    }

    @Test func migratesLegacyKeychainTokenOnceAndNeverQueriesAgain() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "HALink-migrate-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "tokens.json")
        var legacyReadCount = 0
        let store = KeychainStore(
            file: file,
            legacyReader: { address in
                legacyReadCount += 1
                return address == "http://ha.local:8123" ? "legacy-token" : nil
            },
            legacyRemover: { _ in }
        )

        #expect(try store.read(address: "http://ha.local:8123") == "legacy-token")
        #expect(legacyReadCount == 1)

        // Subsequent reads use the local file and never touch Keychain again.
        #expect(try store.read(address: "http://ha.local:8123") == "legacy-token")
        #expect(legacyReadCount == 1)
    }
}
