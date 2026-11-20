import Security
import XCTest
@testable import Keybee

final class StoreTests: XCTestCase {
    private var service = ""

    override func setUp() {
        service = "dev.keybee.sdk.tests.\(UUID().uuidString)"
    }

    override func tearDown() {
        SecItemDelete([kSecClass: kSecClassGenericPassword, kSecAttrService: service] as CFDictionary)
    }

    private func stores() -> [(String, LicenseStore, (Data) -> Void)] {
        let memory = InMemoryStore()
        let keychain = KeychainStore(service: service, dataProtection: false)
        let service = self.service
        return [
            ("memory", memory, { memory.raw = $0 }),
            ("keychain", keychain, { data in
                SecItemDelete([kSecClass: kSecClassGenericPassword, kSecAttrService: service] as CFDictionary)
                let status = SecItemAdd([kSecClass: kSecClassGenericPassword, kSecAttrService: service,
                                         kSecAttrAccount: "license", kSecValueData: data] as CFDictionary, nil)
                XCTAssertEqual(status, errSecSuccess)
            }),
        ]
    }

    private let a = StoredLicense(key: "KB-A", activationID: "act_1", grant: "g.g.g", nonce: "n1", maxIat: 10, maxSeen: 20, adoptionPending: false)
    private let b = StoredLicense(key: "KB-B", activationID: nil, grant: nil, nonce: nil, maxIat: 0, maxSeen: 0, adoptionPending: true)

    func test_emptyThenWriteThenReadThenOverwriteThenDelete() throws {
        for (name, store, _) in stores() {
            XCTAssertEqual(store.read(), .empty, name)
            try store.write(a)
            XCTAssertEqual(store.read(), .found(a), name)
            try store.write(b)
            XCTAssertEqual(store.read(), .found(b), name)
            try store.delete()
            XCTAssertEqual(store.read(), .empty, name)
            try store.delete()
        }
    }

    func test_corruptBytesReadAsCorrupt() {
        for (name, store, plant) in stores() {
            plant(Data("{nope".utf8))
            XCTAssertEqual(store.read(), .corrupt, name)
        }
    }

    func test_newerVersionReadsAsNewerVersion() throws {
        var newer = a
        newer.version = 2
        let data = try JSONEncoder().encode(newer)
        for (name, store, plant) in stores() {
            plant(data)
            XCTAssertEqual(store.read(), .newerVersion, name)
        }
    }
}
