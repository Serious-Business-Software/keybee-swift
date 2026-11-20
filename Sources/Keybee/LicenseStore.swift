import Foundation

/// Keeps the licence in memory only: for previews and tests.
final class InMemoryStore: LicenseStore, @unchecked Sendable {
    private let lock = NSLock()
    private var data: Data?

    init() {}

    /// The stored bytes, settable by tests to plant corrupt data.
    var raw: Data? {
        get { lock.withLock { data } }
        set { lock.withLock { data = newValue } }
    }

    func read() -> StoreRead {
        guard let data = raw else { return .empty }
        return decodeStored(data)
    }

    func write(_ license: StoredLicense) throws(KeybeeError) {
        raw = encodeStored(license)
    }

    func delete() throws(KeybeeError) {
        raw = nil
    }
}
