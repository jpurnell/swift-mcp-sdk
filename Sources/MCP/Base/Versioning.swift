import Foundation

/// The Model Context Protocol uses string-based version identifiers
/// following the format YYYY-MM-DD, to indicate
/// the last date backwards incompatible changes were made.
///
/// - SeeAlso: https://modelcontextprotocol.io/specification/2026-07-28/
public enum Version {
    /// The latest protocol version supported by this implementation.
    ///
    /// Declared directly rather than derived from ``supported``, which previously read
    /// `supported.max()!` — a force unwrap the compiler cannot discharge even though the set
    /// is a non-empty literal. Because the identifiers are `YYYY-MM-DD`, lexicographic order
    /// is chronological order, so this must remain the greatest member of ``supported``;
    /// `VersioningTests` pins both that and membership.
    public static let latest = "2026-07-28"

    /// All protocol versions supported by this implementation, ordered from newest to oldest.
    public static let supported: Set<String> = [
        latest,
        "2025-11-25",
        "2025-06-18",
        "2025-03-26",
        "2024-11-05",
    ]

    /// Negotiates the protocol version based on the client's request and server's capabilities.
    /// - Parameter clientRequestedVersion: The protocol version requested by the client.
    /// - Returns: The negotiated protocol version. If the client's requested version is supported,
    ///            that version is returned. Otherwise, the server's latest supported version is returned.
    static func negotiate(clientRequestedVersion: String) -> String {
        if supported.contains(clientRequestedVersion) {
            return clientRequestedVersion
        }
        return latest
    }
}
