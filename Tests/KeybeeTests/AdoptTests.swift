import XCTest
@testable import Keybee

final class AdoptTests: XCTestCase {
    private var h: Harness!
    private var kb: Keybee!

    override func setUp() {
        h = Harness()
        kb = h.keybee()
    }

    func test_adopt_active_isLicensed() async {
        h.transport.handler = h.answer()
        let state = await kb.adopt(legacyKey: " kb-legacy-1 ")
        guard case .licensed(let l) = state else { return XCTFail("\(state)") }
        XCTAssertEqual(l.key, "KB-LEGACY-1")
        XCTAssertEqual(h.transport.operations, [.activate])
        XCTAssertEqual(h.transport.calls.first?.1.device.fingerprint, sha256Hex("4C4C4544-0035-3010-8052-B3C04F4E3132"))
    }

    func test_adopt_offline_isPending_andCheckRetriesWithActivate() async {
        h.transport.handler = h.offline()
        let pending = await kb.adopt(legacyKey: "KB-LEGACY-1")
        XCTAssertEqual(pending, .adoptionPending)
        let stillPending = await kb.check()
        XCTAssertEqual(stillPending, .adoptionPending)
        h.transport.handler = h.answer()
        let state = await kb.check()
        guard case .licensed(let l) = state else { return XCTFail("\(state)") }
        XCTAssertEqual(l.key, "KB-LEGACY-1")
        XCTAssertEqual(h.transport.operations, [.activate, .activate, .activate])
    }

    func test_adopt_seatLimit_staysPending() async {
        h.transport.handler = h.answer("activation_limit_reached", act: nil, used: 3)
        let state = await kb.adopt(legacyKey: "KB-LEGACY-1")
        XCTAssertEqual(state, .adoptionPending)
        let current = await kb.currentState()
        XCTAssertEqual(current, .adoptionPending)
    }

    func test_adopt_notFound_notActivated_appDisabled_stayPending() async {
        for result in ["not_found", "not_activated", "app_disabled"] {
            let h = Harness(), kb = h.keybee()
            h.transport.handler = h.answer(result, act: nil)
            let state = await kb.adopt(legacyKey: "KB-LEGACY-1")
            XCTAssertEqual(state, .adoptionPending, result)
        }
    }

    func test_adopt_invalidGrantOrServerError_staysPending() async {
        h.transport.handler = h.answer(nonce: "00000000-0000-4000-8000-000000000000")
        let bad = await kb.adopt(legacyKey: "KB-LEGACY-1")
        XCTAssertEqual(bad, .adoptionPending)
        h.transport.handler = { _, _ in throw KeybeeError.server(status: 503, code: "signing_unavailable", requestID: nil) }
        let down = await kb.check()
        XCTAssertEqual(down, .adoptionPending)
    }

    func test_adopt_revoked_isDenied() async {
        for (result, denial) in [("revoked", Denial.revoked), ("refunded", .refunded), ("expired", .expired)] {
            let h = Harness(), kb = h.keybee()
            h.transport.handler = h.answer(result, act: nil, licenseStatus: result)
            let state = await kb.adopt(legacyKey: "KB-LEGACY-1")
            guard case .denied(denial, _) = state else { return XCTFail("\(result): \(state)") }
            let current = await kb.currentState()
            XCTAssertEqual(current, state)
        }
    }

    func test_adopt_whenLicensed_doesNothing() async throws {
        h.transport.handler = h.answer()
        _ = try await kb.activate(key: "KB-AAAA")
        let state = await kb.adopt(legacyKey: "KB-LEGACY-1")
        XCTAssertEqual(state.license?.key, "KB-AAAA")
        XCTAssertEqual(h.transport.operations, [.activate])
    }

    func test_adopt_whenPending_doesNothing() async {
        h.transport.handler = h.offline()
        _ = await kb.adopt(legacyKey: "KB-LEGACY-1")
        _ = await kb.adopt(legacyKey: "KB-LEGACY-1")
        XCTAssertEqual(h.transport.operations, [.activate])
    }

    func test_adopt_afterStoredDenial_runsAgain() async throws {
        h.transport.handler = h.answer("revoked", act: nil, licenseStatus: "revoked")
        _ = await kb.adopt(legacyKey: "KB-LEGACY-1")
        h.transport.handler = h.answer()
        let state = await kb.adopt(legacyKey: "KB-LEGACY-1")
        guard case .licensed = state else { return XCTFail("\(state)") }
    }

    func test_adopt_pending_survivesRelaunch() async {
        h.transport.handler = h.offline()
        _ = await kb.adopt(legacyKey: "KB-LEGACY-1")
        let relaunched = h.keybee()
        let state = await relaunched.currentState()
        XCTAssertEqual(state, .adoptionPending)
    }

    func test_deactivate_whilePending_clearsWithoutRequest() async throws {
        h.transport.handler = h.offline()
        _ = await kb.adopt(legacyKey: "KB-LEGACY-1")
        let state = try await kb.deactivate()
        XCTAssertEqual(state, .unlicensed)
        XCTAssertEqual(h.transport.operations, [.activate])
    }

    func test_isLicensed_offlineGrace() {
        let l = License(key: "K", licenseID: nil, productID: nil, activationID: nil, status: nil, maxActivations: nil, activationsUsed: 0,
                        grantExpiresAt: Date(), refreshAfter: Date(), isTestMode: false)
        let table: [(LicenseState, Bool, Bool)] = [
            (.unlicensed, false, false),
            (.licensed(l), true, true),
            (.denied(.revoked, l), false, false),
            (.needsValidation(l), false, true),
            (.needsValidation(nil), false, false),
            (.adoptionPending, false, false),
            (.storageUnavailable, false, false),
        ]
        for (state, lifetime, untilReconnect) in table {
            XCTAssertEqual(state.isLicensed(), lifetime, "\(state)")
            XCTAssertEqual(state.isLicensed(offlineGrace: .grantLifetime), lifetime, "\(state)")
            XCTAssertEqual(state.isLicensed(offlineGrace: .untilReconnect), untilReconnect, "\(state)")
        }
    }
}

/// A store that reads empty and refuses every write, like a data protection
/// Keychain without the entitlement.
final class FailingWriteStore: LicenseStore {
    func read() -> StoreRead { .empty }
    func write(_ license: StoredLicense) throws(KeybeeError) { throw .storage(-34018) }
    func delete() throws(KeybeeError) {}
}

final class AdoptStorageFailureTests: XCTestCase {
    func test_adopt_writeFails_neverReportsAnUnsavedAnswer() async {
        let h = Harness()
        let clock = h.clock
        let kb = Keybee(h.configuration, transport: h.transport, store: FailingWriteStore(), now: { clock.date },
                        hardwareUUID: "4C4C4544-0035-3010-8052-B3C04F4E3132", bundleID: "com.example.app",
                        device: DeviceInfo(name: "Mac", appVersion: "1.0"))
        h.transport.handler = h.answer()
        let active = await kb.adopt(legacyKey: "KB-LEGACY-1")
        XCTAssertEqual(active, .adoptionPending, "an answer that was not saved must not tell the app to delete its old licence")
        h.transport.handler = h.answer("revoked", act: nil, licenseStatus: "revoked")
        let revoked = await kb.adopt(legacyKey: "KB-LEGACY-1")
        XCTAssertEqual(revoked, .adoptionPending)
    }
}
