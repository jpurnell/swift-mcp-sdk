import Foundation

#if canImport(CryptoKit)
    import CryptoKit
#endif

#if canImport(Security)
    import Security
#endif

/// Pure PKCE (RFC 7636) helpers required by the authorization_code flow.
public enum PKCE {

    /// Generates a cryptographically random PKCE code verifier.
    ///
    /// - Parameter length: Number of characters in the verifier. Defaults to 64.
    ///   RFC 7636 requires 43–128 characters.
    /// - Returns: A URL-safe random string suitable for use as a PKCE code verifier.
    public static func makeVerifier(length: Int = 64) -> String {
        var generator = SecureRandomNumberGenerator()
        return makeVerifier(length: length, using: &generator)
    }

    /// Generates a PKCE code verifier from a caller-supplied random number generator.
    ///
    /// Production callers should use ``makeVerifier(length:)``, which draws from the
    /// system's cryptographically secure source. Supplying a seeded generator makes the
    /// result reproducible, which is useful in tests.
    ///
    /// - Parameters:
    ///   - length: Number of characters in the verifier. RFC 7636 requires 43–128 characters.
    ///   - generator: The random number generator to draw bytes from.
    /// - Returns: A URL-safe random string suitable for use as a PKCE code verifier.
    public static func makeVerifier(length: Int, using generator: inout some RandomNumberGenerator)
        -> String
    {
        let charset = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        // 66 characters; 256 % 66 == 52, so reject bytes > 252 to eliminate modulo bias.
        let limit = UInt8(255 - (255 % charset.count))  // 252
        var result = ""
        result.reserveCapacity(length)
        while result.count < length {
            let byte = UInt8.random(in: 0...255, using: &generator)
            if byte <= limit {
                result.append(charset[Int(byte % UInt8(charset.count))])
            }
        }
        return result
    }

    /// Generates an unguessable OAuth `state` value: 32 random bytes, base64url-encoded.
    ///
    /// The `state` parameter is the client's CSRF defence, so it must be a secret-quality
    /// random value rather than an identifier such as a UUID.
    static func makeStateToken() -> String {
        var generator = SecureRandomNumberGenerator()
        return makeStateToken(using: &generator)
    }

    /// Generates a `state` value from the supplied generator (32 bytes, base64url, 43 characters).
    static func makeStateToken(using generator: inout some RandomNumberGenerator) -> String {
        var bytes = [UInt8]()
        bytes.reserveCapacity(32)
        for _ in 0..<32 {
            bytes.append(UInt8.random(in: 0...255, using: &generator))
        }
        return Data(bytes).base64URLEncodedString()
    }

    /// Derives the PKCE S256 code challenge from a verifier.
    ///
    /// - Parameter verifier: A code verifier produced by ``makeVerifier(length:)``.
    /// - Returns: The base64url-encoded SHA-256 hash of the verifier.
    /// - Throws: ``OAuthAuthorizationError/pkceS256Unavailable`` on platforms without CryptoKit.
    public static func makeChallenge(from verifier: String) throws -> String {
        #if canImport(CryptoKit)
            let hash = SHA256.hash(data: Data(verifier.utf8))
            return Data(hash).base64URLEncodedString()
        #else
            throw OAuthAuthorizationError.pkceS256Unavailable
        #endif
    }

    /// Verifies that the authorization server metadata advertises S256 PKCE support.
    ///
    /// - Parameter metadata: Authorization server metadata to inspect.
    /// - Throws: ``OAuthAuthorizationError/pkceCodeChallengeMethodsMissing`` if
    ///   `code_challenge_methods_supported` is absent or empty, or
    ///   ``OAuthAuthorizationError/pkceS256NotSupported(advertisedMethods:)`` if S256 is not listed.
    static func checkSupport(in metadata: OAuthAuthorizationServerMetadata) throws {
        guard let methods = metadata.codeChallengeMethodsSupported, !methods.isEmpty else {
            throw OAuthAuthorizationError.pkceCodeChallengeMethodsMissing
        }
        let supportsS256 = methods.contains {
            $0.caseInsensitiveCompare(OAuthCodeChallengeMethod.s256) == .orderedSame
        }
        guard supportsS256 else {
            throw OAuthAuthorizationError.pkceS256NotSupported(advertisedMethods: methods)
        }
    }
}

/// Random number generator backed by the operating system's cryptographically secure source.
///
/// Call sites accept any `RandomNumberGenerator` (tests inject a seeded one) and default to this
/// one in production. Apple platforms read `SecRandomCopyBytes`; other platforms read
/// `/dev/urandom`.
struct SecureRandomNumberGenerator: RandomNumberGenerator {
    mutating func next() -> UInt64 {
        var bytes = [UInt8](repeating: 0, count: MemoryLayout<UInt64>.size)
        #if canImport(Security)
            let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
            precondition(status == errSecSuccess, "SecRandomCopyBytes failed; no secure random bytes")
        #else
            guard let source = FileHandle(forReadingAtPath: "/dev/urandom") else {
                preconditionFailure("/dev/urandom unreadable; no secure random bytes")
            }
            let data: Data
            do {
                data = try source.read(upToCount: bytes.count) ?? Data()
            } catch {
                preconditionFailure("/dev/urandom read failed (\(error)); no secure random bytes")
            }
            precondition(data.count == bytes.count, "/dev/urandom returned too few bytes")
            bytes = Array(data)
        #endif
        return bytes.reduce(0) { ($0 << 8) | UInt64($1) }
    }
}
