import Foundation

/// What the SDK keeps on this Mac. A pending adoption has no grant yet.
struct StoredLicense: Codable, Sendable, Equatable {
    var version: Int = 1
    var key: String
    var activationID: String?
    var grant: String?
    /// The nonce of the request that returned `grant`.
    var nonce: String?
    /// The highest `iat` of any grant accepted (keybee's clock).
    var maxIat: Int
    /// The greatest device time seen.
    var maxSeen: Int
    var adoptionPending: Bool

    static let currentVersion = 1
}

enum StoreRead: Sendable, Equatable {
    case empty
    case found(StoredLicense)
    case corrupt
    case newerVersion
    case unavailable(OSStatus)
}

protocol LicenseStore: Sendable {
    func read() -> StoreRead
    func write(_ license: StoredLicense) throws(KeybeeError)
    func delete() throws(KeybeeError)
}

func decodeStored(_ data: Data) -> StoreRead {
    struct Versioned: Decodable { let version: Int }
    guard let versioned = try? JSONDecoder().decode(Versioned.self, from: data) else { return .corrupt }
    guard versioned.version <= StoredLicense.currentVersion else { return .newerVersion }
    guard let license = try? JSONDecoder().decode(StoredLicense.self, from: data) else { return .corrupt }
    return .found(license)
}

func encodeStored(_ license: StoredLicense) -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    // Encoding a struct of strings and integers cannot fail.
    return (try? encoder.encode(license)) ?? Data()
}
