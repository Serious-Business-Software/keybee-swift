import Foundation

/// Why a grant was rejected. Raw values match the `reason` field of keybee's
/// published grant vectors.
public enum GrantRejection: String, Error, Sendable, Equatable {
    case format, alg, typ, kid, signature, aud, device, nonce, expired
}

/// Errors from `activate`, `deactivate` and configuration. An error never
/// changes what is stored.
public enum KeybeeError: Error, Sendable, Equatable {
    /// keybee could not be reached.
    case network(URLError.Code)
    /// keybee answered with something other than a usable 200.
    case server(status: Int, code: String?, requestID: String?)
    /// keybee's answer did not verify. `.expired` on a fresh answer usually
    /// means the Mac's clock is far ahead.
    case invalidGrant(GrantRejection)
    /// No usable device fingerprint.
    case deviceUnavailable
    /// The Keychain refused a read or write.
    case storage(OSStatus)
}
