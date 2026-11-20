import Foundation

/// A public key the app embeds, as listed by `GET /v2/apps/{app_id}/jwks`.
public struct KeybeePublicKey: Sendable, Hashable {
    public let kid: String
    /// The key's `x` value, base64url.
    public let x: String

    public init(kid: String, x: String) {
        self.kid = kid
        self.x = x
    }
}

/// Where the licence is kept on this Mac.
public enum KeybeeStorageLocation: Sendable, Equatable {
    /// The Keychain. `service` defaults to "<bundle id>.keybee". The data
    /// protection Keychain needs the keychain-access-groups entitlement.
    case keychain(service: String? = nil, dataProtection: Bool = false)
    /// In memory only, for previews and tests.
    case memory
}

public struct KeybeeConfiguration: Sendable {
    /// `app_live_...` or `app_test_...`.
    public var appID: String
    /// Every key your account publishes for this app's mode.
    public var publicKeys: [KeybeePublicKey]
    public var fingerprint: DeviceFingerprint
    public var storage: KeybeeStorageLocation
    public var baseURL: URL

    public init(
        appID: String,
        publicKeys: [KeybeePublicKey],
        fingerprint: DeviceFingerprint = .hardware,
        storage: KeybeeStorageLocation = .keychain(),
        baseURL: URL = URL(string: "https://api.keybee.app")!
    ) {
        self.appID = appID
        self.publicKeys = publicKeys
        self.fingerprint = fingerprint
        self.storage = storage
        self.baseURL = baseURL
    }

    public var isTestMode: Bool { appID.hasPrefix("app_test_") }
}
