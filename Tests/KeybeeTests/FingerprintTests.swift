import XCTest
@testable import Keybee

final class FingerprintTests: XCTestCase {
    func test_v1Compatible_hashesTheRawUUIDString() throws {
        let uuid = "4C4C4544-0035-3010-8052-B3C04F4E3132"
        XCTAssertEqual(try DeviceFingerprint.v1Compatible.resolve(hardwareUUID: uuid, bundleID: "x"), sha256Hex(uuid))
    }

    func test_v1Compatible_fallsBackToUnknownMac() throws {
        XCTAssertEqual(try DeviceFingerprint.v1Compatible.resolve(hardwareUUID: nil, bundleID: "x"), sha256Hex("unknown-mac"))
    }

    func test_hardware_mixesTheBundleID() throws {
        XCTAssertEqual(try DeviceFingerprint.hardware.resolve(hardwareUUID: "U", bundleID: "com.example.app"), sha256Hex("U|com.example.app"))
    }

    func test_hardware_withoutUUID_throwsDeviceUnavailable() {
        XCTAssertThrowsError(try DeviceFingerprint.hardware.resolve(hardwareUUID: nil, bundleID: "b")) {
            XCTAssertEqual($0 as? KeybeeError, .deviceUnavailable)
        }
    }

    func test_exact_acceptsOnly64LowercaseHex() throws {
        let ok = String(repeating: "a", count: 64)
        XCTAssertEqual(try DeviceFingerprint.exact(ok).resolve(hardwareUUID: nil, bundleID: "b"), ok)
        for bad in [String(repeating: "A", count: 64), String(repeating: "a", count: 63), String(repeating: "g", count: 64), ""] {
            XCTAssertThrowsError(try DeviceFingerprint.exact(bad).resolve(hardwareUUID: nil, bundleID: "b"))
        }
    }

    func test_sha256Hex_knownValue() {
        XCTAssertEqual(sha256Hex("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    func test_configuration_testMode() {
        XCTAssertTrue(KeybeeConfiguration(appID: "app_test_X", publicKeys: []).isTestMode)
        XCTAssertFalse(KeybeeConfiguration(appID: "app_live_X", publicKeys: []).isTestMode)
    }
}
