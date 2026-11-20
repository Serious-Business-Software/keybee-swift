import XCTest
@testable import Keybee

final class TransportTests: XCTestCase {
    private let transport = URLSessionTransport(baseURL: URL(string: "https://api.example.test")!, session: StubProtocol.session())
    private let fingerprint = String(repeating: "f", count: 64)

    override func setUp() {
        StubProtocol.requests = []
        StubProtocol.reply = .init(status: 200, body: Data(#"{"result":"active","license":null,"activation_id":"act_1","grant":"a.b.c"}"#.utf8))
    }

    private func body(activationID: String? = nil) -> DeviceRequest {
        DeviceRequest.make(appID: "app_test_X", key: "  kb-abcd-efgh \n", fingerprint: fingerprint,
                           device: DeviceInfo(name: "Mac", appVersion: "1.2"), nonce: "n-1", activationID: activationID)
    }

    private func sentJSON() throws -> [String: Any] {
        let data = try XCTUnwrap(StubProtocol.requests.last?.1)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func test_requestShape() async throws {
        let reply = try await transport.send(.activate, body())
        XCTAssertEqual(reply.result, "active")
        XCTAssertEqual(reply.activation_id, "act_1")
        XCTAssertEqual(reply.grant, "a.b.c")
        let request = try XCTUnwrap(StubProtocol.requests.last?.0)
        XCTAssertEqual(request.url?.absoluteString, "https://api.example.test/v2/activate")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "keybee-swift/0.1.0")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let json = try sentJSON()
        XCTAssertEqual(json["app_id"] as? String, "app_test_X")
        XCTAssertEqual(json["key"] as? String, "KB-ABCD-EFGH")
        XCTAssertEqual(json["nonce"] as? String, "n-1")
        XCTAssertNil(json["activation_id"])
        let device = try XCTUnwrap(json["device"] as? [String: Any])
        XCTAssertEqual(device["fingerprint"] as? String, fingerprint)
        XCTAssertEqual(device["name"] as? String, "Mac")
        XCTAssertEqual(device["platform"] as? String, "macos")
        XCTAssertEqual(device["app_version"] as? String, "1.2")
    }

    func test_deactivateSendsActivationID() async throws {
        _ = try await transport.send(.deactivate, body(activationID: "act_1"))
        XCTAssertEqual(StubProtocol.requests.last?.0.url?.path, "/v2/deactivate")
        XCTAssertEqual(try sentJSON()["activation_id"] as? String, "act_1")
    }

    func test_non200MapsToServerErrorWithCodeAndRequestID() async {
        StubProtocol.reply = .init(status: 429, headers: ["Keybee-Request-Id": "req_1"],
                                   body: Data(#"{"error":{"type":"rate_limited","code":"rate_limited","message":"x","request_id":"req_1"}}"#.utf8))
        await assertThrows(.server(status: 429, code: "rate_limited", requestID: "req_1"))
    }

    func test_htmlBodyOn502MapsToServerErrorWithoutCode() async {
        StubProtocol.reply = .init(status: 502, body: Data("<html>bad gateway</html>".utf8))
        await assertThrows(.server(status: 502, code: nil, requestID: nil))
    }

    func test_200WithoutGrantIsUnparsable() async {
        StubProtocol.reply = .init(status: 200, body: Data(#"{"result":"active"}"#.utf8))
        await assertThrows(.server(status: 200, code: "unparsable_reply", requestID: nil))
    }

    func test_urlErrorMapsToNetwork() async {
        StubProtocol.reply = .init(error: URLError(.notConnectedToInternet))
        await assertThrows(.network(.notConnectedToInternet))
    }

    private func assertThrows(_ expected: KeybeeError, file: StaticString = #filePath, line: UInt = #line) async {
        do {
            _ = try await transport.send(.validate, body())
            XCTFail("did not throw", file: file, line: line)
        } catch {
            XCTAssertEqual(error, expected, file: file, line: line)
        }
    }
}
