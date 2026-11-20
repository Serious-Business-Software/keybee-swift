import Foundation

/// What keybee last said about this Mac's licence, as far as it can be
/// trusted right now.
public enum LicenseState: Sendable, Equatable {
    /// No licence on this Mac.
    case unlicensed
    /// A verified `active` answer that has not expired.
    case licensed(License)
    /// An authentic no. The licence is included when keybee found one.
    case denied(Denial, License?)
    /// The stored answer has expired or can no longer be verified, and keybee
    /// could not be reached. The licence is included only when the last
    /// verified answer was `active`.
    case needsValidation(License?)
    /// Moving from keybee's earlier API has not reached keybee yet. Keep using
    /// the app's previous answer.
    case adoptionPending
    /// The Keychain could not be read right now (for example, before the
    /// first unlock after a restart). Not the same as unlicensed.
    case storageUnavailable
}

public struct License: Sendable, Equatable {
    public let key: String
    public let licenseID: String?
    public let productID: String?
    /// This Mac's seat.
    public let activationID: String?
    /// `active`, `revoked`, `refunded` or `expired`.
    public let status: String?
    /// nil means unlimited.
    public let maxActivations: Int?
    public let activationsUsed: Int
    /// The stored answer is not valid at or after this time.
    public let grantExpiresAt: Date
    /// After this, the SDK asks keybee again when it can.
    public let refreshAfter: Date
    public let isTestMode: Bool
}

/// Why keybee said no.
public enum Denial: Sendable, Equatable {
    case notFound, revoked, refunded, expired, notActivated, activationLimitReached, appDisabled
    /// A result this version of the SDK does not know. Still an authentic no.
    case other(String)

    init(result: String) {
        switch result {
        case "not_found": self = .notFound
        case "revoked": self = .revoked
        case "refunded": self = .refunded
        case "expired": self = .expired
        case "not_activated": self = .notActivated
        case "activation_limit_reached": self = .activationLimitReached
        case "app_disabled": self = .appDisabled
        default: self = .other(result)
        }
    }
}

/// How long a Mac that cannot reach keybee keeps its licence.
public enum OfflineGrace: Sendable {
    /// Until the stored answer expires (30 days after the last check by
    /// default), as keybee's Grants page describes.
    case grantLifetime
    /// For as long as it takes to reconnect. Show a "connect to the internet
    /// to confirm your licence" note while the state is `needsValidation`.
    case untilReconnect
}

extension LicenseState {
    /// Whether to unlock paid features. `adoptionPending` is false: during a
    /// move from keybee's earlier API, the app decides from its old storage.
    public func isLicensed(offlineGrace: OfflineGrace = .grantLifetime) -> Bool {
        switch self {
        case .licensed:
            return true
        case .needsValidation(.some):
            return offlineGrace == .untilReconnect
        default:
            return false
        }
    }
}
