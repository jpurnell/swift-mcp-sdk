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
    /// Returns the currently stored token.
    ///
    /// The authorizer calls this before requests, so implementations should be cheap and safe to call from
    /// any thread.
    ///
    /// - Returns: The most recently saved token, or `nil` if none has been saved or it was cleared.
    func load() -> OAuthAccessToken?
    /// Removes the stored token, for example when the authorization server changes or the token is rejected.
    ///
    /// After this call ``load()`` returns `nil` until a new token is saved.
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

    /// Creates a storage that holds no token.
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
