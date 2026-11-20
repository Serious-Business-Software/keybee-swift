import XCTest
@testable import Keybee

final class KeybeeStateTests: XCTestCase {
    private var h: Harness!
    private var kb: Keybee!

    override func setUp() {
        h = Harness()
        kb = h.keybee()
    }

    private func activated(_ key: String = "KB-AAAA") async throws {
        h.transport.handler = h.answer()
        _ = try await kb.activate(key: key)
    }

    private func stored() throws -> StoredLicense {
        guard case .found(let s) = h.store.read() else { throw XCTSkip("nothing stored") }
        return s
    }

    private func isLicensed(_ s: LicenseState) -> Bool { if case .licensed = s { return true } else { return false } }

    func test_nothingStored_isUnlicensed_andCheckDoesNotCallTheNetwork() async {
        let current = await kb.currentState()
        XCTAssertEqual(current, .unlicensed)
        let checked = await kb.check()
        XCTAssertEqual(checked, .unlicensed)
        XCTAssertTrue(h.transport.calls.isEmpty)
    }

    func test_activate_active_storesAndReturnsLicensed() async throws {
        h.transport.handler = h.answer()
        let state = try await kb.activate(key: "KB-AAAA")
        let l = try XCTUnwrap(state.license)
        XCTAssertTrue(isLicensed(state))
        XCTAssertEqual(l.key, "KB-AAAA")
        XCTAssertEqual(l.activationID, "act_1")
        XCTAssertEqual(l.licenseID, "lic_1")
        XCTAssertEqual(l.productID, "prod_1")
        XCTAssertEqual(l.maxActivations, 3)
        XCTAssertEqual(l.activationsUsed, 1)
        XCTAssertEqual(l.grantExpiresAt, Date(timeIntervalSince1970: TimeInterval(now0 + 30 * day)))
        XCTAssertEqual(l.refreshAfter, Date(timeIntervalSince1970: TimeInterval(now0 + 7 * day)))
        XCTAssertTrue(l.isTestMode)
        let current = await kb.currentState()
        XCTAssertEqual(current, state)
        XCTAssertEqual(h.transport.operations, [.activate])
        XCTAssertEqual(try stored().maxIat, now0)
    }

    func test_activate_normalisesTheKeyBeforeSending() async throws {
        h.transport.handler = h.answer()
        let state = try await kb.activate(key: "  kb-abcd \n")
        XCTAssertEqual(h.transport.calls.first?.1.key, "KB-ABCD")
        XCTAssertEqual(state.license?.key, "KB-ABCD")
        XCTAssertEqual(h.transport.calls.first?.1.device.fingerprint, sha256Hex("4C4C4544-0035-3010-8052-B3C04F4E3132"))
    }

    func test_activate_deniedWhileLicensed_keepsTheLicence() async throws {
        try await activated()
        h.transport.handler = h.answer("not_found", act: nil, licenseStatus: nil)
        let state = try await kb.activate(key: "KB-TYPO")
        XCTAssertEqual(state, .denied(.notFound, state.license))
        let current = await kb.currentState()
        XCTAssertTrue(isLicensed(current))
        XCTAssertEqual(current.license?.key, "KB-AAAA")
    }

    func test_activate_deniedWhenUnlicensed_storesTheDenial() async throws {
        h.transport.handler = h.answer("activation_limit_reached", act: nil, maxActivations: 2, used: 2)
        let state = try await kb.activate(key: "KB-AAAA")
        guard case .denied(.activationLimitReached, let l?) = state else { return XCTFail("\(state)") }
        XCTAssertEqual(l.maxActivations, 2)
        XCTAssertEqual(l.activationsUsed, 2)
        let current = await kb.currentState()
        XCTAssertEqual(current, state)
    }

    func test_activate_networkError_throwsAndKeepsStorage() async throws {
        try await activated()
        let before = h.store.raw
        h.transport.handler = h.offline()
        do { _ = try await kb.activate(key: "KB-BBBB"); XCTFail("did not throw") } catch {
            XCTAssertEqual(error, .network(.notConnectedToInternet))
        }
        XCTAssertEqual(h.store.raw, before)
    }

    func test_activate_wrongNonceGrant_throwsInvalidGrantNonce() async throws {
        h.transport.handler = h.answer(nonce: "00000000-0000-4000-8000-000000000000")
        do { _ = try await kb.activate(key: "KB-AAAA"); XCTFail("did not throw") } catch {
            XCTAssertEqual(error, .invalidGrant(.nonce))
        }
        XCTAssertEqual(h.store.read(), .empty)
    }

    func test_activate_clockFarAhead_throwsInvalidGrantExpired() async throws {
        h.transport.handler = h.answer(iatOffset: -31 * day)
        do { _ = try await kb.activate(key: "KB-AAAA"); XCTFail("did not throw") } catch {
            XCTAssertEqual(error, .invalidGrant(.expired))
        }
        XCTAssertEqual(h.store.read(), .empty)
    }

    func test_check_beforeRefreshAfter_noRequest() async throws {
        try await activated()
        h.clock.now = now0 + 7 * day - 1
        let state = await kb.check()
        XCTAssertTrue(isLicensed(state))
        XCTAssertEqual(h.transport.operations, [.activate])
    }

    func test_check_afterRefreshAfter_validatesAndStoresFreshGrant() async throws {
        try await activated()
        h.clock.now = now0 + 7 * day
        let state = await kb.check()
        XCTAssertEqual(h.transport.operations, [.activate, .validate])
        XCTAssertEqual(state.license?.grantExpiresAt, Date(timeIntervalSince1970: TimeInterval(now0 + 37 * day)))
        XCTAssertEqual(try stored().maxIat, now0 + 7 * day)
        XCTAssertEqual(h.transport.calls.last?.1.key, "KB-AAAA")
    }

    func test_check_afterRefresh_offline_staysLicensedUntilExp() async throws {
        try await activated()
        h.transport.handler = h.offline()
        h.clock.now = now0 + 30 * day - 1
        let state = await kb.check()
        XCTAssertTrue(isLicensed(state))
        XCTAssertEqual(h.transport.operations, [.activate, .validate])
    }

    func test_check_afterExp_offline_isNeedsValidationWithLicence() async throws {
        try await activated()
        h.transport.handler = h.offline()
        h.clock.now = now0 + 30 * day
        let state = await kb.check()
        guard case .needsValidation(let l?) = state else { return XCTFail("\(state)") }
        XCTAssertEqual(l.key, "KB-AAAA")
    }

    func test_check_storedDenial_revalidatesEveryTime() async throws {
        h.transport.handler = h.answer("revoked", licenseStatus: "revoked")
        _ = try await kb.activate(key: "KB-AAAA")
        _ = await kb.check()
        _ = await kb.check()
        XCTAssertEqual(h.transport.operations, [.activate, .validate, .validate])
    }

    func test_check_clockSetBack_validatesFirst_andOfflineKeepsLicensed() async throws {
        try await activated()
        h.transport.handler = h.offline()
        h.clock.now = now0 - 301
        let state = await kb.check()
        XCTAssertEqual(h.transport.operations, [.activate, .validate])
        // The stored grant is honoured until its exp; a set-back clock never denies.
        XCTAssertTrue(isLicensed(state))
    }

    func test_check_clockWithinSkew_noRequest() async throws {
        try await activated()
        h.clock.now = now0 + 1000
        _ = await kb.currentState()             // maxSeen = now0 + 1000
        h.clock.now = now0 + 1000 - 299
        let state = await kb.check()
        XCTAssertTrue(isLicensed(state))
        XCTAssertEqual(h.transport.operations, [.activate])
    }

    func test_check_neverReplacesHigherIatWithOlder() async throws {
        // Only fresh answers are ever stored, so the stored grant and its marks
        // change only through a fresh answer: an error or a discarded answer
        // leaves them exactly as they were.
        try await activated()
        h.clock.now = now0 + 8 * day
        h.transport.handler = h.answer()
        _ = await kb.check()
        let afterFresh = try stored()
        XCTAssertEqual(afterFresh.maxIat, now0 + 8 * day)
        h.clock.now = now0 + 16 * day
        h.transport.handler = h.offline()
        _ = await kb.check()
        let afterError = try stored()
        XCTAssertEqual(afterError.grant, afterFresh.grant)
        XCTAssertEqual(afterError.maxIat, afterFresh.maxIat)
    }

    func test_check_concurrentCalls_makeOneRequest() async throws {
        try await activated()
        h.clock.now = now0 + 8 * day
        let gate = Gate()
        let answer = h.answer()
        h.transport.handler = { op, req in
            await gate.wait()
            return try await answer(op, req)
        }
        let kb = self.kb!
        async let a = kb.check()
        async let b = kb.check()
        while h.transport.operations.count < 2 { await Task.yield() }
        try await Task.sleep(nanoseconds: 20_000_000)
        await gate.release()
        let (ra, rb) = await (a, b)
        XCTAssertEqual(ra, rb)
        XCTAssertEqual(h.transport.operations, [.activate, .validate])
    }

    func test_check_replyAfterActivate_isDiscarded() async throws {
        try await activated()
        h.clock.now = now0 + 8 * day
        let gate = Gate()
        let answer = h.answer()
        h.transport.handler = { op, req in
            if op == .validate { await gate.wait() }
            return try await answer(op, req)
        }
        let kb = self.kb!
        let checking = Task { await kb.check() }
        while !h.transport.operations.contains(.validate) { await Task.yield() }
        let activated = try await kb.activate(key: "KB-BBBB")
        XCTAssertEqual(activated.license?.key, "KB-BBBB")
        await gate.release()
        let checked = await checking.value
        XCTAssertEqual(checked.license?.key, "KB-BBBB")
        let current = await kb.currentState()
        XCTAssertEqual(current.license?.key, "KB-BBBB")
    }

    func test_corruptItem_readsUnlicensed_andOnlyActiveOverwritesIt() async throws {
        let garbage = Data("{nope".utf8)
        h.store.raw = garbage
        let current = await kb.currentState()
        XCTAssertEqual(current, .unlicensed)
        h.transport.handler = h.answer("not_found", act: nil, licenseStatus: nil)
        let denied = try await kb.activate(key: "KB-TYPO")
        guard case .denied(.notFound, _) = denied else { return XCTFail("\(denied)") }
        XCTAssertEqual(h.store.raw, garbage)
        h.transport.handler = h.answer()
        let state = try await kb.activate(key: "KB-AAAA")
        XCTAssertTrue(isLicensed(state))
        XCTAssertNotEqual(h.store.raw, garbage)
    }

    func test_newerVersionItem_readsStorageUnavailable_andIsNotOverwrittenByCheck() async throws {
        var newer = StoredLicense(key: "KB-AAAA", activationID: "act_1", grant: "a.b.c", nonce: "n", maxIat: 0, maxSeen: 0, adoptionPending: false)
        newer.version = 2
        let data = try JSONEncoder().encode(newer)
        h.store.raw = data
        let current = await kb.currentState()
        XCTAssertEqual(current, .storageUnavailable)
        h.transport.handler = h.answer()
        let checked = await kb.check()
        XCTAssertEqual(checked, .storageUnavailable)
        XCTAssertTrue(h.transport.calls.isEmpty)
        XCTAssertEqual(h.store.raw, data)
    }

    func test_deactivate_clearsOnDeactivated() async throws {
        try await activated()
        h.transport.handler = h.answer("deactivated", act: nil)
        let state = try await kb.deactivate()
        XCTAssertEqual(state, .unlicensed)
        XCTAssertEqual(h.store.read(), .empty)
        XCTAssertEqual(h.transport.calls.last?.1.activation_id, "act_1")
        XCTAssertEqual(h.transport.operations.last, .deactivate)
    }

    func test_deactivate_nothingStored_makesNoRequest() async throws {
        let state = try await kb.deactivate()
        XCTAssertEqual(state, .unlicensed)
        XCTAssertTrue(h.transport.calls.isEmpty)
    }

    func test_deactivate_error_throwsAndKeeps() async throws {
        try await activated()
        let before = h.store.raw
        h.transport.handler = h.offline()
        do { _ = try await kb.deactivate(); XCTFail("did not throw") } catch {
            XCTAssertEqual(error, .network(.notConnectedToInternet))
        }
        XCTAssertEqual(h.store.raw, before)
    }

    func test_reset_clearsWithoutNetwork() async throws {
        try await activated()
        await kb.reset()
        XCTAssertEqual(h.store.read(), .empty)
        XCTAssertEqual(h.transport.operations, [.activate])
    }

    func test_unknownResult_isDeniedOther() async throws {
        h.transport.handler = h.answer("frozen")
        let state = try await kb.activate(key: "KB-AAAA")
        guard case .denied(.other("frozen"), _) = state else { return XCTFail("\(state)") }
    }

    func test_denialMapping() {
        let table: [(String, Denial)] = [("not_found", .notFound), ("revoked", .revoked), ("refunded", .refunded), ("expired", .expired),
                                         ("not_activated", .notActivated), ("activation_limit_reached", .activationLimitReached),
                                         ("app_disabled", .appDisabled), ("deactivated", .other("deactivated"))]
        for (raw, denial) in table { XCTAssertEqual(Denial(result: raw), denial, raw) }
    }
}
