import Foundation

// MARK: - Token Storage Protocol

/// Abstraction for persisting OAuth access tokens.
///
/// Implement this protocol to provide custom token storage (e.g., Keychain-backed).
/// The default ``InMemoryTokenStorage`` stores tokens in memory only.
public protocol TokenStorage: AnyObject, Sendable {
    /// Persists `token`, replacing any previously stored token.
    ///
    /// - Parameter token: The access token to store.
    func save(_ token: OAuthAccessToken)
    /// Returns the stored token, or `nil` if there is none.
    func load() -> OAuthAccessToken?
    /// Removes the stored token.
    func clear()
}

// MARK: - In-Memory Implementation

/// Default ``TokenStorage`` that stores the access token in memory only.
///
/// The token is lost when the process exits. For persistent storage
/// (e.g., system Keychain), implement ``TokenStorage`` directly.
// Justification: the stored token is read and written only through the actor-isolated TokenStorage requirements
public final class InMemoryTokenStorage: TokenStorage, @unchecked Sendable {
    private var token: OAuthAccessToken?

    /// Creates an empty storage.
    public init() {}

    /// Stores `token`, replacing any previously stored token.
    ///
    /// - Parameter token: The access token to store.
    public func save(_ token: OAuthAccessToken) {
        self.token = token
    }

    /// Returns the stored token, or `nil` if none has been saved or it was cleared.
    public func load() -> OAuthAccessToken? {
        token
    }

    /// Discards the stored token.
    public func clear() {
        token = nil
    }
}
