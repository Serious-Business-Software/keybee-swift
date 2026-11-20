import XCTest
@testable import Keybee

struct GrantVector: Decodable {
    let name: String
    let grant: String
    let app_id: String
    let device: String
    let nonce: String
    let now: Int
    let expect: String
    let reason: String?
    let refresh: Bool?
    let result: String?
}

func resourceURL(_ name: String) throws -> URL {
    try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Resources"))
}

func loadVectors() throws -> [GrantVector] {
    try JSONDecoder().decode([GrantVector].self, from: Data(contentsOf: resourceURL("grants.json")))
}

func loadVectorKeys() throws -> [KeybeePublicKey] {
    struct JWKS: Decodable { struct Key: Decodable { let kid: String; let x: String }; let keys: [Key] }
    return try JSONDecoder().decode(JWKS.self, from: Data(contentsOf: resourceURL("jwk.json"))).keys.map { KeybeePublicKey(kid: $0.kid, x: $0.x) }
}

final class GrantVectorTests: XCTestCase {
    func test_everyPublishedVector() throws {
        let vectors = try loadVectors()
        let keys = try loadVectorKeys()
        XCTAssertEqual(vectors.count, 19)
        for v in vectors {
            let r = GrantVerifier.verify(v.grant, keys: keys, appID: v.app_id, device: v.device, nonce: v.nonce, now: v.now)
            switch (v.expect, r) {
            case ("accept", .success(let c)):
                XCTAssertEqual(c.result, v.result, v.name)
                XCTAssertEqual(needsRefresh(c, now: v.now), v.refresh, v.name)
            case ("reject", .failure(let why)):
                XCTAssertEqual(why.rawValue, v.reason, v.name)
            default:
                XCTFail("\(v.name): expected \(v.expect), got \(r)")
            }
        }
    }

    func test_rejectsTwoPartsAndGarbage() {
        for g in ["a.b", "a.b.c.d", "", "...", "e30.e30.AA", "eyJhbGciOiJFZERTQSJ9.e30"] {
            if case .success = GrantVerifier.verify(g, keys: [], appID: "a", device: "d", nonce: "n", now: 0) {
                XCTFail("accepted \(g)")
            }
        }
    }
}
