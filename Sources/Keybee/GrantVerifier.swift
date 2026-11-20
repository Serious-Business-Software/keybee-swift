import CryptoKit
import Foundation

/// Verifies a grant exactly as keybee's Grants page says, rejecting at the
/// first check that fails.
enum GrantVerifier {
    private struct Header: Decodable {
        let alg: String?
        let typ: String?
        let kid: String?
    }

    static func verify(
        _ grant: String,
        keys: [KeybeePublicKey],
        appID: String,
        device: String,
        nonce: String,
        now: Int
    ) -> Result<GrantClaims, GrantRejection> {
        // 1. Three parts; the first two decode to JSON objects.
        let parts = grant.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3,
              let headerData = Base64URL.decode(parts[0]),
              let payloadData = Base64URL.decode(parts[1]),
              let signature = Base64URL.decode(parts[2]),
              isJSONObject(headerData), isJSONObject(payloadData),
              let header = try? JSONDecoder().decode(Header.self, from: headerData)
        else { return .failure(.format) }

        // 2-4. Algorithm, type, key id.
        guard header.alg == "EdDSA" else { return .failure(.alg) }
        guard header.typ == "kb-grant+jwt" else { return .failure(.typ) }
        guard let key = keys.first(where: { $0.kid == header.kid }) else { return .failure(.kid) }

        // 5. Ed25519 over the ASCII bytes of header.payload exactly as received.
        guard let raw = Base64URL.decode(key.x),
              let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: raw),
              publicKey.isValidSignature(signature, for: Data((parts[0] + "." + parts[1]).utf8))
        else { return .failure(.signature) }

        guard let claims = try? JSONDecoder().decode(GrantClaims.self, from: payloadData) else { return .failure(.format) }

        // 6-9. Audience, device, nonce, expiry.
        guard claims.aud == appID else { return .failure(.aud) }
        guard claims.device == device else { return .failure(.device) }
        guard claims.nonce == nonce else { return .failure(.nonce) }
        guard now < claims.exp else { return .failure(.expired) }
        return .success(claims)
    }

    private static func isJSONObject(_ data: Data) -> Bool {
        (try? JSONSerialization.jsonObject(with: data)) is [String: Any]
    }
}
