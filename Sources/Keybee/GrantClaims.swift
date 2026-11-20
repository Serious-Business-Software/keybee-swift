import Foundation

/// A grant's payload. Unknown claims are ignored.
struct GrantClaims: Decodable, Sendable, Equatable {
    let iss: String
    let sub: String?
    let aud: String
    let prd: String?
    let iat: Int
    let exp: Int
    let refresh_after: Int
    let nonce: String
    let device: String
    let act: String?
    let result: String
    let license_status: String?
    let max_activations: Int?
    let activations_used: Int
}

func needsRefresh(_ claims: GrantClaims, now: Int) -> Bool {
    now >= claims.refresh_after
}
