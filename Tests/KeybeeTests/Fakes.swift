import CryptoKit
import Foundation
import XCTest
@testable import Keybee

/// Signs a grant the way keybee does, with a test key.
func makeGrant(_ claims: [String: Any], key: Curve25519.Signing.PrivateKey, kid: String,
               header: [String: Any]? = nil) -> String {
    let h = header ?? ["alg": "EdDSA", "kid": kid, "typ": "kb-grant+jwt"]
    let part0 = Base64URL.encode(try! JSONSerialization.data(withJSONObject: h, options: .sortedKeys))
    let part1 = Base64URL.encode(try! JSONSerialization.data(withJSONObject: claims, options: .sortedKeys))
    let signature = try! key.signature(for: Data((part0 + "." + part1).utf8))
    return part0 + "." + part1 + "." + Base64URL.encode(signature)
}

/// A URLProtocol that answers every request with a scripted reply and records
/// what was sent.
final class StubProtocol: URLProtocol, @unchecked Sendable {
    struct Reply: Sendable {
        var status = 200
        var headers: [String: String] = [:]
        var body = Data()
        var error: URLError?
    }

    nonisolated(unsafe) static var reply = Reply()
    nonisolated(unsafe) static var requests: [(URLRequest, Data)] = []

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var body = request.httpBody ?? Data()
        if body.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            var buffer = [UInt8](repeating: 0, count: 65536)
            while stream.hasBytesAvailable {
                let n = stream.read(&buffer, maxLength: buffer.count)
                if n <= 0 { break }
                body.append(buffer, count: n)
            }
            stream.close()
        }
        Self.requests.append((request, body))
        let reply = Self.reply
        if let error = reply.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: reply.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Int
    init(_ now: Int) { value = now }
    var now: Int {
        get { lock.withLock { value } }
        set { lock.withLock { value = newValue } }
    }
    var date: Date { Date(timeIntervalSince1970: TimeInterval(now)) }
}

/// Records every request and answers with a replaceable handler.
final class FakeTransport: Transport, @unchecked Sendable {
    typealias Handler = @Sendable (DeviceOperation, DeviceRequest) async throws -> DeviceReply
    private let lock = NSLock()
    private var _handler: Handler = { _, _ in throw KeybeeError.network(.notConnectedToInternet) }
    private var _calls: [(DeviceOperation, DeviceRequest)] = []

    var handler: Handler {
        get { lock.withLock { _handler } }
        set { lock.withLock { _handler = newValue } }
    }
    var calls: [(DeviceOperation, DeviceRequest)] { lock.withLock { _calls } }
    var operations: [DeviceOperation] { calls.map(\.0) }

    func send(_ operation: DeviceOperation, _ body: DeviceRequest) async throws(KeybeeError) -> DeviceReply {
        lock.withLock { _calls.append((operation, body)) }
        do {
            return try await handler(operation, body)
        } catch let error as KeybeeError {
            throw error
        } catch {
            throw .network(.unknown)
        }
    }
}

/// A one-shot gate a fake handler can wait on.
actor Gate {
    private var open = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if open { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func release() {
        open = true
        waiters.forEach { $0.resume() }
        waiters = []
    }
}

let day = 86_400
let now0 = 1_800_000_000

/// A Keybee wired to fakes, plus helpers that sign keybee-style answers.
final class Harness: @unchecked Sendable {
    let signingKey = Curve25519.Signing.PrivateKey()
    let kid = "sig_test_0001"
    let appID = "app_test_Harness0000000000000000"
    let store = InMemoryStore()
    let clock = TestClock(now0)
    let transport = FakeTransport()

    var configuration: KeybeeConfiguration {
        KeybeeConfiguration(appID: appID, publicKeys: [KeybeePublicKey(kid: kid, x: Base64URL.encode(signingKey.publicKey.rawRepresentation))],
                            fingerprint: .v1Compatible, storage: .memory)
    }

    func keybee() -> Keybee {
        let clock = self.clock
        return Keybee(configuration, transport: transport, store: store, now: { clock.date },
                      hardwareUUID: "4C4C4544-0035-3010-8052-B3C04F4E3132", bundleID: "com.example.app",
                      device: DeviceInfo(name: "Mac", appVersion: "1.0"))
    }

    /// A handler that answers every request with a signed `result`.
    func answer(_ result: String = "active", act: String? = "act_1", iatOffset: Int = 0, nonce: String? = nil,
                maxActivations: Int? = 3, used: Int = 1, licenseStatus: String? = "active") -> FakeTransport.Handler {
        let raw = signingKey.rawRepresentation
        let kid = self.kid, appID = self.appID, clock = self.clock
        return { _, request in
            let key = try! Curve25519.Signing.PrivateKey(rawRepresentation: raw)
            let iat = clock.now + iatOffset
            let claims: [String: Any] = [
                "iss": "acct_test", "sub": result == "not_found" ? NSNull() : "lic_1", "aud": appID,
                "prd": result == "not_found" ? NSNull() : "prod_1",
                "iat": iat, "exp": iat + 30 * day, "refresh_after": iat + 7 * day,
                "nonce": nonce ?? request.nonce, "device": request.device.fingerprint,
                "act": act.map { $0 as Any } ?? NSNull(), "result": result,
                "license_status": licenseStatus.map { $0 as Any } ?? NSNull(),
                "max_activations": maxActivations.map { $0 as Any } ?? NSNull(), "activations_used": used,
            ]
            return DeviceReply(result: result, activation_id: act, grant: makeGrant(claims, key: key, kid: kid))
        }
    }

    func offline() -> FakeTransport.Handler {
        { _, _ in throw KeybeeError.network(.notConnectedToInternet) }
    }
}

extension LicenseState {
    var license: License? {
        switch self {
        case .licensed(let l): return l
        case .denied(_, let l), .needsValidation(let l): return l
        default: return nil
        }
    }
}
