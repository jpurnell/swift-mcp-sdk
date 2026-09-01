import Foundation

/// Tells a client how to parse a result.
///
/// Introduced by MCP `2026-07-28` (SEP-2322). A server implementing that revision **must**
/// include it on every result. A client receiving a result from a server on an earlier
/// revision, where the field is absent, **must** treat it as ``complete`` — see
/// ``resolving(_:)``.
///
/// - SeeAlso: https://modelcontextprotocol.io/specification/2026-07-28/
public enum ResultType: String, Hashable, Codable, Sendable {
    /// The request completed and the result holds the final content.
    case complete
    /// The request needs more input; the result holds an input-required object describing what
    /// the client must supply before retrying.
    case inputRequired = "input_required"

    /// Resolves an optional tag to the value the specification says it means.
    ///
    /// An absent tag is `complete`. Keeping that rule here means every reader gets it, rather
    /// than each call site rediscovering that `nil` is not "unknown".
    public static func resolving(_ resultType: ResultType?) -> ResultType {
        resultType ?? .complete
    }
}
