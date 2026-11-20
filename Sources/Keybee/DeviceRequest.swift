import Foundation

enum DeviceOperation: String, Sendable {
    case activate, validate, deactivate
}

/// The body of `POST /v2/activate`, `/v2/validate` and `/v2/deactivate`.
struct DeviceRequest: Encodable, Sendable, Equatable {
    struct Device: Encodable, Sendable, Equatable {
        let fingerprint: String
        let name: String
        let platform: String
        let app_version: String?
    }

    let app_id: String
    let key: String
    let device: Device
    let nonce: String
    let activation_id: String?

    static func make(appID: String, key: String, fingerprint: String, device: DeviceInfo, nonce: String, activationID: String?) -> DeviceRequest {
        DeviceRequest(
            app_id: appID,
            key: normalizeKey(key),
            device: Device(fingerprint: fingerprint, name: device.name, platform: "macos", app_version: device.appVersion),
            nonce: nonce,
            activation_id: activationID
        )
    }
}

/// Keys are sent trimmed and uppercased, whatever case the buyer typed or an
/// older build stored.
func normalizeKey(_ key: String) -> String {
    key.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
}

func newNonce() -> String {
    UUID().uuidString.lowercased()
}
