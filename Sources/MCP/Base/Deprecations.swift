import Foundation

/// Features MCP `2026-07-28` places in its Deprecated state, and what to use instead.
///
/// ## Why these are documented rather than marked `@available(*, deprecated)`
///
/// The specification's feature lifecycle says a deprecated feature "remains fully functional
/// during the deprecation window" — a minimum of twelve months — and that "new implementations
/// should not add support for them". That guidance is aimed at someone **building a server on
/// this SDK**, not at the SDK itself, which must keep implementing every one of these so that
/// existing peers keep working.
///
/// A Swift `@available(*, deprecated)` attribute cannot express that difference. It warns at
/// every use site, including this SDK's own required support and the tests that exercise it —
/// roughly eighty of them — which would report the correct behaviour as a mistake and make a
/// warning-free build impossible for every consumer. So the deprecations are recorded here and
/// in the doc comments of the types themselves, where they reach the people the specification is
/// actually addressing.
///
/// Revisit when the removal date is set: at that point the attribute becomes correct, because
/// the SDK will genuinely be dropping support rather than maintaining it.
///
/// ## Deprecated in `2026-07-28`
///
/// | Feature | Migration |
/// | --- | --- |
/// | Roots | Pass directories or files as tool parameters, resource URIs, or server configuration |
/// | Sampling | Integrate directly with an LLM provider's API |
/// | Logging | Log to `stderr` over stdio, or use OpenTelemetry |
/// | HTTP+SSE transport | Use Streamable HTTP. Deprecated since `2025-03-26`; reclassified here |
/// | `includeContext` values `thisServer` and `allServers` | Omit the field, or use `none` |
/// | OAuth Dynamic Client Registration | Use Client ID Metadata Documents |
///
/// Removed outright in this revision, and so absent from the table above rather than deprecated:
/// the `initialize` handshake, protocol-level sessions, `ping`, `logging/setLevel`,
/// `resources/subscribe`, `resources/unsubscribe`, SSE resumability, and the core tasks methods.
///
/// - SeeAlso: https://modelcontextprotocol.io/specification/2026-07-28/deprecated
public enum Deprecations {
    /// The protocol revision that deprecated the features described here.
    public static let deprecatedIn = "2026-07-28"
}
