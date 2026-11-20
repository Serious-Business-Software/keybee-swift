import Foundation
import XCTest
@testable import Keybee

/// Runs against production in test mode (no email, no charge). Opt in with
/// KEYBEE_LIVE_TEST=1 and KEYBEE_TEST_APP_ID=app_test_...
final class LiveTests: XCTestCase {
    private func setUpLive() async throws -> (KeybeeConfiguration, String) {
        let env = ProcessInfo.processInfo.environment
        guard env["KEYBEE_LIVE_TEST"] == "1", let appID = env["KEYBEE_TEST_APP_ID"] else {
            throw XCTSkip("set KEYBEE_LIVE_TEST=1 and KEYBEE_TEST_APP_ID to run")
        }
        struct JWKS: Decodable { struct Key: Decodable { let kid: String; let x: String }; let keys: [Key] }
        let url = URL(string: "https://api.keybee.app/v2/apps/\(appID)/jwks")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let keys = try JSONDecoder().decode(JWKS.self, from: data).keys.map { KeybeePublicKey(kid: $0.kid, x: $0.x) }
        let fingerprint = sha256Hex("keybee-swift-live-test")
        return (KeybeeConfiguration(appID: appID, publicKeys: keys, fingerprint: .exact(fingerprint), storage: .memory), fingerprint)
    }

    private func keybee(_ configuration: KeybeeConfiguration, store: LicenseStore, offset: TimeInterval = 0) -> Keybee {
        Keybee(configuration, transport: URLSessionTransport(baseURL: configuration.baseURL), store: store,
               now: { Date().addingTimeInterval(offset) }, hardwareUUID: nil, bundleID: "dev.keybee.sdk.live-test",
               device: DeviceInfo(name: "keybee-swift live test", appVersion: "0.1.0"))
    }

    func test_activateCheckDeactivate() async throws {
        let (configuration, _) = try await setUpLive()
        let store = InMemoryStore()
        let kb = keybee(configuration, store: store)
        let activated = try await kb.activate(key: "KB-TEST-PASS-2222-2222")
        guard case .licensed(let first) = activated else { return XCTFail("\(activated)") }
        XCTAssertTrue(first.isTestMode)

        try await Task.sleep(nanoseconds: 1_100_000_000)
        let later = keybee(configuration, store: store, offset: 8 * 86_400)
        let checked = await later.check()
        guard case .licensed(let second) = checked else { return XCTFail("\(checked)") }
        XCTAssertGreaterThan(second.grantExpiresAt, first.grantExpiresAt)

        let deactivated = try await kb.deactivate()
        XCTAssertEqual(deactivated, .unlicensed)
    }

    func test_seatLimitKey() async throws {
        let (configuration, _) = try await setUpLive()
        let kb = keybee(configuration, store: InMemoryStore())
        let state = try await kb.activate(key: "KB-TEST-MAXD-2222-2222")
        guard case .denied(.activationLimitReached, _) = state else { return XCTFail("\(state)") }
    }
}
