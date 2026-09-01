import Foundation

/// The intended sharing scope of a cached response.
///
/// Analogous to HTTP `Cache-Control: public` versus `Cache-Control: private`.
///
/// - SeeAlso: https://modelcontextprotocol.io/specification/2026-07-28/
public enum CacheScope: String, Hashable, Codable, Sendable {
    /// The response may be cached and reused only within the same authorization context.
    ///
    /// Caches must not be shared across authorization contexts — a different access token
    /// requires a different cache entry.
    case `private`
    /// The response contains no user-specific data.
    ///
    /// Any client or intermediary, such as a shared gateway or caching proxy, may cache the
    /// response and serve it across authorization contexts.
    case `public`
}

/// A result that carries a hint about how long a client may cache it.
///
/// Introduced by MCP `2026-07-28` (SEP-2549) on the list and read results, to let clients
/// cache responses and reduce polling. Both fields complement the existing `listChanged`
/// notifications rather than replacing them.
///
/// ## Why these are optional
///
/// The specification marks `ttlMs` and `cacheScope` as **required** for a server implementing
/// `2026-07-28`. They are modelled as optional because the same Swift types serve clients on
/// earlier revisions, which must not receive these keys at all. The requirement is therefore a
/// protocol obligation enforced where a `2026-07-28` response is composed — not a constraint
/// the type system can express while both revisions are served from one implementation.
public protocol CacheableResult {
    /// How long, in milliseconds, the client may consider this result fresh.
    ///
    /// Zero means the result should be treated as immediately stale, and the client may
    /// re-fetch every time it is needed. A zero is therefore meaningful and is encoded, not
    /// omitted as though it were absent.
    var ttlMs: Int? { get }

    /// Whether a shared intermediary may cache this result.
    var cacheScope: CacheScope? { get }
}
