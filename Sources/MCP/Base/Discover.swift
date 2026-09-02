import Foundation

/// A request asking the server to advertise its supported protocol versions, capabilities and
/// metadata.
///
/// Introduced by MCP `2026-07-28` (SEP-2575). **Servers must implement it.** Clients may call it
/// before any other request to select a protocol version up front, or use it as a
/// backward-compatibility probe — version negotiation can also happen inline through per-request
/// `_meta`.
///
/// Discovery is what removes the need for the `initialize` handshake that earlier revisions
/// required, and it is what allows one implementation to serve `2026-07-28` alongside earlier
/// revisions: a client that understands discovery asks, and one that does not still sends
/// `initialize`.
///
/// - SeeAlso: https://modelcontextprotocol.io/specification/2026-07-28/
public enum Discover: Method {
    /// The JSON-RPC method name.
    public static let name: String = "server/discover"

    /// What the server advertises about itself.
    public struct Result: Hashable, Codable, Sendable, CacheableResult {
        /// Every protocol version this server accepts, newest first.
        ///
        /// A client selects from this set. Each entry must be one that negotiation will
        /// actually honour — advertising a version the server would refuse is worse than not
        /// advertising it, because the client has no other signal.
        public let supportedVersions: [String]
        /// The capabilities of the server.
        public let capabilities: Server.Capabilities
        /// Natural-language guidance describing the server and its features.
        ///
        /// Intended to help a model use the server effectively — for instance by being placed
        /// in a system prompt — and should not restate what tool descriptions already say.
        public let instructions: String?
        /// Optional metadata about this result.
        public var _meta: Metadata?
        /// Tells the client how to parse this result.
        public var resultType: ResultType?
        /// How long, in milliseconds, the client may consider this result fresh.
        public var ttlMs: Int?
        /// Whether a shared intermediary may cache this result.
        public var cacheScope: CacheScope?

        /// Creates a discovery result.
        ///
        /// The parameter count reflects the schema: `2026-07-28` marks `supportedVersions`,
        /// `capabilities`, `resultType`, `ttlMs` and `cacheScope` all required on this result,
        /// and `instructions` and `_meta` are optional additions. Grouping them into a
        /// sub-structure would hide which fields the specification requires.
        // legibility:reserved the parameter list mirrors the schema's required fields
        public init(
            supportedVersions: [String],
            capabilities: Server.Capabilities,
            instructions: String? = nil,
            _meta: Metadata? = nil,
            resultType: ResultType? = .complete,
            ttlMs: Int? = nil,
            cacheScope: CacheScope? = nil
        ) {
            self.supportedVersions = supportedVersions
            self.capabilities = capabilities
            self.instructions = instructions
            self._meta = _meta
            self.resultType = resultType
            self.ttlMs = ttlMs
            self.cacheScope = cacheScope
        }

        private enum CodingKeys: String, CodingKey {
            case supportedVersions, capabilities, instructions, _meta, resultType, ttlMs, cacheScope
        }

        /// Encodes the result, omitting any field the server did not set.
        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(supportedVersions, forKey: .supportedVersions)
            try container.encode(capabilities, forKey: .capabilities)
            try container.encodeIfPresent(instructions, forKey: .instructions)
            try container.encodeIfPresent(_meta, forKey: ._meta)
            try container.encodeIfPresent(resultType, forKey: .resultType)
            try container.encodeIfPresent(ttlMs, forKey: .ttlMs)
            try container.encodeIfPresent(cacheScope, forKey: .cacheScope)
        }

        /// Decodes a discovery result, tolerating fields an earlier revision omits.
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            supportedVersions = try container.decode([String].self, forKey: .supportedVersions)
            capabilities = try container.decode(Server.Capabilities.self, forKey: .capabilities)
            instructions = try container.decodeIfPresent(String.self, forKey: .instructions)
            _meta = try container.decodeIfPresent(Metadata.self, forKey: ._meta)
            // An unrecognised tag from a future revision reads as absent rather than throwing.
            resultType = try? container.decodeIfPresent(ResultType.self, forKey: .resultType)
            ttlMs = try container.decodeIfPresent(Int.self, forKey: .ttlMs)
            cacheScope = try container.decodeIfPresent(CacheScope.self, forKey: .cacheScope)
        }
    }
}
