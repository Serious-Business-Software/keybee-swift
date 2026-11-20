import CryptoKit
import Foundation
import IOKit

/// How this device identifies itself to keybee. The result is always 64
/// lowercase hex characters, and must stay the same on this device, because a
/// new fingerprint costs the buyer a seat.
public enum DeviceFingerprint: Sendable, Equatable {
    /// SHA-256 of the Mac's hardware UUID and the app's bundle identifier.
    /// The default for new apps.
    case hardware
    /// SHA-256 of the hardware UUID string alone (or of "unknown-mac" when it
    /// is unavailable): what keybee matches against seats claimed through its
    /// earlier API, so an app moving from it keeps its buyers' seats.
    case v1Compatible
    /// A fingerprint the app supplies, already 64 lowercase hex characters.
    case exact(String)

    func resolve(hardwareUUID: String?, bundleID: String) throws(KeybeeError) -> String {
        switch self {
        case .hardware:
            guard let uuid = hardwareUUID, !uuid.isEmpty else { throw .deviceUnavailable }
            return sha256Hex(uuid + "|" + bundleID)
        case .v1Compatible:
            guard let uuid = hardwareUUID, !uuid.isEmpty else { return sha256Hex("unknown-mac") }
            return sha256Hex(uuid)
        case .exact(let value):
            guard isFingerprint(value) else { throw .deviceUnavailable }
            return value
        }
    }
}

func isFingerprint(_ value: String) -> Bool {
    value.utf8.count == 64 && value.utf8.allSatisfy { (0x30...0x39).contains($0) || (0x61...0x66).contains($0) }
}

func sha256Hex(_ string: String) -> String {
    SHA256.hash(data: Data(string.utf8)).map { String(format: "%02x", $0) }.joined()
}

/// The Mac's `IOPlatformUUID`, exactly as IOKit returns it.
func readHardwareUUID() -> String? {
    let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
    guard service != 0 else { return nil }
    defer { IOObjectRelease(service) }
    let value = IORegistryEntryCreateCFProperty(service, kIOPlatformUUIDKey as CFString, kCFAllocatorDefault, 0)
    return value?.takeRetainedValue() as? String
}
