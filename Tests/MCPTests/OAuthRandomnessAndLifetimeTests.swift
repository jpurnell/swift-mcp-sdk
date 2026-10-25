import Foundation
import Testing

@testable import MCP

/// Deterministic SplitMix64 generator so randomness-dependent code can be tested.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

@Suite("OAuth randomness and assertion lifetime")
struct OAuthRandomnessAndLifetimeTests {
    private let endpoint = testURL("https://auth.example.com/token")
    private let pem = "not-a-real-key"

    @Test("Non-finite or absurd lifetimes throw invalidLifetime instead of trapping", arguments: [
        TimeInterval.nan, .infinity, 1e300,
    ])
    func rejectsUnrepresentableLifetime(lifetime: TimeInterval) {
        #expect(throws: OAuthConfiguration.PrivateKeyJWTAssertionError.self) {
            _ = try OAuthConfiguration.makePrivateKeyJWTAssertion(
                clientID: "c", tokenEndpoint: endpoint, privateKeyPEM: pem, expiresIn: lifetime)
        }
    }

    @Test("Seeded verifier is reproducible and RFC 7636 shaped")
    func seededVerifier() {
        var a = SeededGenerator(seed: 7)
        var b = SeededGenerator(seed: 7)
        let first = PKCE.makeVerifier(length: 64, using: &a)
        let second = PKCE.makeVerifier(length: 64, using: &b)
        #expect(first == second)
        #expect(first.count == 64)
    }

    @Test("Seeded redirect URI is reproducible and in the ephemeral port range")
    func seededRedirect() throws {
        var a = SeededGenerator(seed: 11)
        var b = SeededGenerator(seed: 11)
        let first = OAuthConfiguration.defaultAuthorizationRedirectURI(using: &a)
        let second = OAuthConfiguration.defaultAuthorizationRedirectURI(using: &b)
        #expect(first == second)
        let port = try #require(first.port)
        #expect((49152...65535).contains(port))
    }

    @Test("State token is 32 random bytes in base64url, not a UUID")
    func stateToken() {
        var a = SeededGenerator(seed: 3)
        let state = PKCE.makeStateToken(using: &a)
        #expect(state.count == 43)
        #expect(UUID(uuidString: state) == nil)
        #expect(state.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
        var c = SeededGenerator(seed: 4)
        #expect(PKCE.makeStateToken(using: &c) != state)
        #expect(PKCE.makeStateToken() != PKCE.makeStateToken())
    }
}
