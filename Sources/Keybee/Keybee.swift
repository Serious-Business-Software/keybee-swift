import Foundation

/// keybee licensing for one app. Call `check()` at launch, `activate(key:)`
/// when the buyer enters a key, and `deactivate()` to free this Mac's seat.
public actor Keybee {
    private let configuration: KeybeeConfiguration
    private let transport: Transport
    private let store: LicenseStore
    private let now: @Sendable () -> Date
    private let hardwareUUID: String?
    private let bundleID: String
    private let device: DeviceInfo

    /// Bumped whenever a fresh answer is stored or the licence is cleared, so
    /// a `check()` whose answer arrives after the buyer acted is discarded.
    private var generation = 0
    private var inFlightCheck: Task<LicenseState, Never>?

    public init(_ configuration: KeybeeConfiguration) {
        let bundleID = Bundle.main.bundleIdentifier ?? ""
        let store: LicenseStore
        switch configuration.storage {
        case .memory:
            store = InMemoryStore()
        case .keychain(let service, let dataProtection):
            store = KeychainStore(service: service ?? "\(bundleID.isEmpty ? "keybee" : bundleID).keybee", dataProtection: dataProtection)
        }
        self.init(configuration, transport: URLSessionTransport(baseURL: configuration.baseURL), store: store, now: { Date() },
                  hardwareUUID: readHardwareUUID(), bundleID: bundleID, device: DeviceInfo.current())
    }

    init(_ configuration: KeybeeConfiguration, transport: Transport, store: LicenseStore, now: @escaping @Sendable () -> Date,
         hardwareUUID: String?, bundleID: String, device: DeviceInfo) {
        self.configuration = configuration
        self.transport = transport
        self.store = store
        self.now = now
        self.hardwareUUID = hardwareUUID
        self.bundleID = bundleID
        self.device = device
    }

    // MARK: Public

    /// The licence as stored, without touching the network.
    public func currentState() -> LicenseState {
        switch store.read() {
        case .empty, .corrupt:
            return .unlicensed
        case .newerVersion, .unavailable:
            return .storageUnavailable
        case .found(var stored):
            if stored.adoptionPending { return .adoptionPending }
            let t = seconds()
            if t > stored.maxSeen {
                stored.maxSeen = t
                try? store.write(stored)
            }
            return state(of: stored, at: t)
        }
    }

    /// Call at launch and now and then while the app runs. Asks keybee when
    /// the stored answer is due for a refresh, has expired, is a denial, or the
    /// clock looks set back. Never throws: without keybee it returns the
    /// stored answer, so a licensed Mac stays licensed until the answer expires.
    public func check() async -> LicenseState {
        if let running = inFlightCheck { return await running.value }
        let task = Task { await self.performCheck() }
        inFlightCheck = task
        let result = await task.value
        if inFlightCheck == task { inFlightCheck = nil }
        return result
    }

    /// Activates a key on this Mac. A denial is returned; it replaces what is
    /// stored only when this Mac has no working licence, so a mistyped key
    /// never costs the buyer theirs. Throws when keybee gave no usable answer,
    /// leaving everything stored as it was.
    public func activate(key: String) async throws(KeybeeError) -> LicenseState {
        let fresh = try await ask(.activate, key: key, activationID: nil)
        if fresh.claims.result == "active" {
            try save(fresh)
            return state(of: fresh)
        }
        if mayStoreDenial() { try save(fresh) }
        return state(of: fresh)
    }

    /// Frees this Mac's seat and forgets the licence. Throws when keybee could
    /// not be reached, keeping the licence so the buyer can try again; call
    /// `reset()` to forget it locally anyway.
    public func deactivate() async throws(KeybeeError) -> LicenseState {
        let stored: StoredLicense
        switch store.read() {
        case .empty, .corrupt:
            clear()
            return .unlicensed
        case .newerVersion:
            throw .storage(errSecDecode)
        case .unavailable(let status):
            throw .storage(status)
        case .found(let s):
            stored = s
        }
        guard let activationID = stored.activationID else {
            clear()
            return .unlicensed
        }
        let fresh = try await ask(.deactivate, key: stored.key, activationID: activationID)
        switch fresh.claims.result {
        case "deactivated", "not_activated":
            try store.delete()
            generation += 1
            return .unlicensed
        default:
            try save(fresh)
            return state(of: fresh)
        }
    }

    /// Forgets the licence on this Mac without asking keybee. The seat stays
    /// claimed until the buyer frees it elsewhere.
    public func reset() {
        clear()
    }

    // MARK: Check

    private func performCheck() async -> LicenseState {
        let stored: StoredLicense
        switch store.read() {
        case .empty, .corrupt:
            return .unlicensed
        case .newerVersion, .unavailable:
            return .storageUnavailable
        case .found(let s):
            stored = s
        }
        if stored.adoptionPending { return await retryAdoption(stored) }

        let t = seconds()
        let clockSetBack = t + 300 < stored.maxIat || t + 300 < stored.maxSeen
        let current = currentState()
        var due = clockSetBack
        switch current {
        case .licensed(let license):
            if t >= Int(license.refreshAfter.timeIntervalSince1970) { due = true }
        default:
            due = true
        }
        guard due else { return current }

        let fresh: Fresh
        do {
            fresh = try await ask(.validate, key: stored.key, activationID: stored.activationID)
        } catch {
            return currentState()
        }
        guard fresh.generation == generation else { return currentState() }
        try? save(fresh)
        return state(of: fresh)
    }

    // MARK: Adoption

    /// Moves a licence from keybee's earlier API. Pass the key the app already
    /// has; configure the fingerprint as `.v1Compatible` (or `.exact`) so this
    /// Mac's existing seat is recognised. Safe to call at every launch until the
    /// app deletes its old storage: it does nothing once this Mac has a
    /// licence or a move is pending.
    ///
    /// Returns `adoptionPending` while keybee cannot confirm the licence
    /// (offline, or the seller's setup not ready, or the seat limit reached):
    /// keep using the app's previous answer meanwhile. `check()` retries.
    /// Only an authentic revoked, refunded or expired answer is a `denied`.
    public func adopt(legacyKey: String) async -> LicenseState {
        switch store.read() {
        case .newerVersion, .unavailable:
            return .storageUnavailable
        case .found(let stored) where stored.adoptionPending:
            return .adoptionPending
        default:
            break
        }
        switch currentState() {
        case .licensed, .needsValidation(.some):
            return currentState()
        default:
            break
        }
        let pending = StoredLicense(key: normalizeKey(legacyKey), activationID: nil, grant: nil, nonce: nil,
                                    maxIat: 0, maxSeen: seconds(), adoptionPending: true)
        try? store.write(pending)
        generation += 1
        return await retryAdoption(pending)
    }

    func retryAdoption(_ stored: StoredLicense) async -> LicenseState {
        let fresh: Fresh
        do {
            fresh = try await ask(.activate, key: stored.key, activationID: nil)
        } catch {
            return .adoptionPending
        }
        guard fresh.generation == generation else { return currentState() }
        switch fresh.claims.result {
        case "active", "revoked", "refunded", "expired":
            // The app deletes its old licence once this says licensed or
            // denied, so only say so when the answer is safely stored.
            do {
                try save(fresh)
            } catch {
                return .adoptionPending
            }
            return state(of: fresh)
        default:
            // activation_limit_reached, not_found, not_activated, app_disabled
            // or an unknown result: the seller's side, not the buyer's licence.
            return .adoptionPending
        }
    }

    // MARK: Requests

    struct Fresh: Sendable {
        let claims: GrantClaims
        let grant: String
        let nonce: String
        let key: String
        /// The generation when the request was sent.
        let generation: Int
    }

    /// Sends a request and verifies the answer against the nonce just sent.
    func ask(_ operation: DeviceOperation, key: String, activationID: String?) async throws(KeybeeError) -> Fresh {
        let fingerprint = try configuration.fingerprint.resolve(hardwareUUID: hardwareUUID, bundleID: bundleID)
        let nonce = newNonce()
        let body = DeviceRequest.make(appID: configuration.appID, key: key, fingerprint: fingerprint, device: device,
                                      nonce: nonce, activationID: activationID)
        let sentAt = generation
        let reply = try await transport.send(operation, body)
        switch GrantVerifier.verify(reply.grant, keys: configuration.publicKeys, appID: configuration.appID,
                                    device: fingerprint, nonce: nonce, now: seconds()) {
        case .failure(let reason):
            throw .invalidGrant(reason)
        case .success(let claims):
            return Fresh(claims: claims, grant: reply.grant, nonce: nonce, key: body.key, generation: sentAt)
        }
    }

    // MARK: Storage

    func save(_ fresh: Fresh) throws(KeybeeError) {
        try store.write(StoredLicense(key: fresh.key, activationID: fresh.claims.act, grant: fresh.grant, nonce: fresh.nonce,
                                      maxIat: fresh.claims.iat, maxSeen: seconds(), adoptionPending: false))
        generation += 1
    }

    func clear() {
        try? store.delete()
        generation += 1
    }

    /// A denial may replace what is stored only when nothing usable is there:
    /// no licence (not a corrupt item, which only an active answer replaces),
    /// a denial, or an expired answer that was not a licence.
    private func mayStoreDenial() -> Bool {
        if case .empty = store.read() { return true }
        switch currentState() {
        case .denied, .needsValidation(nil): return true
        default: return false
        }
    }

    // MARK: States

    func seconds() -> Int {
        Int(now().timeIntervalSince1970.rounded(.down))
    }

    private func state(of stored: StoredLicense, at t: Int) -> LicenseState {
        guard let grant = stored.grant, let nonce = stored.nonce,
              let fingerprint = try? configuration.fingerprint.resolve(hardwareUUID: hardwareUUID, bundleID: bundleID)
        else { return .needsValidation(nil) }
        let verify = { (time: Int) in
            GrantVerifier.verify(grant, keys: self.configuration.publicKeys, appID: self.configuration.appID,
                                 device: fingerprint, nonce: nonce, now: time)
        }
        switch verify(t) {
        case .success(let claims):
            return state(claims: claims, key: stored.key)
        case .failure(.expired):
            // Authentic but expired: say what it last was, if it was a licence.
            if case .success(let claims) = verify(Int.min), claims.result == "active" {
                return .needsValidation(license(claims, key: stored.key))
            }
            return .needsValidation(nil)
        case .failure:
            return .needsValidation(nil)
        }
    }

    func state(of fresh: Fresh) -> LicenseState {
        state(claims: fresh.claims, key: fresh.key)
    }

    private func state(claims: GrantClaims, key: String) -> LicenseState {
        let license = license(claims, key: key)
        if claims.result == "active" { return .licensed(license) }
        return .denied(Denial(result: claims.result), claims.sub == nil ? nil : license)
    }

    private func license(_ claims: GrantClaims, key: String) -> License {
        License(key: key, licenseID: claims.sub, productID: claims.prd, activationID: claims.act, status: claims.license_status,
                maxActivations: claims.max_activations, activationsUsed: claims.activations_used,
                grantExpiresAt: Date(timeIntervalSince1970: TimeInterval(claims.exp)),
                refreshAfter: Date(timeIntervalSince1970: TimeInterval(claims.refresh_after)),
                isTestMode: configuration.isTestMode)
    }
}
