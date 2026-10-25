import Foundation

/// The Model Context Protocol (MCP) provides a mechanism for clients to expose
/// filesystem boundaries to servers through roots. Roots allow servers to understand
/// the scope of filesystem access they can request, enabling safe and controlled
/// file operations.
///
/// Unlike Resources/Tools/Prompts, Roots use bidirectional communication:
/// - Servers send `roots/list` requests TO clients
/// - Clients respond with available roots
/// - Clients send `notifications/roots/list_changed` when roots change
///
/// - SeeAlso: https://modelcontextprotocol.io/specification/2025-11-25/client/roots
public struct Root: Hashable, Codable, Sendable {
    /// The root URI. The spec requires the `file://` scheme; this type does not enforce it.
    public let uri: String
    /// Optional human-readable name for the root
    public let name: String?
    /// Optional metadata
    public var _meta: Metadata?

    /// Creates a filesystem root to expose to a server in a `roots/list` response.
    ///
    /// - Parameters:
    ///   - uri: The root's URI, e.g. `file:///Users/me/project`. The spec requires `file://`; not validated.
    ///   - name: Human-readable label for display. Defaults to `nil`; omitted from the wire when `nil`.
    ///   - _meta: Protocol-reserved metadata. Defaults to `nil`; omitted from the wire when `nil`.
    public init(
        uri: String,
        name: String? = nil,
        _meta: Metadata? = nil
    ) {
        self.uri = uri
        self.name = name
        self._meta = _meta
    }

    private enum CodingKeys: String, CodingKey {
        case uri
        case name
        case _meta
    }

    /// Decodes a root from a keyed container.
    ///
    /// Required: `uri`. Optional: `name`, `_meta`. The `uri` is not validated for the `file://` scheme.
    ///
    /// - Parameter decoder: The decoder to read the value from.
    /// - Throws: `DecodingError` if `uri` is missing or any key has the wrong type.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        uri = try container.decode(String.self, forKey: .uri)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        _meta = try container.decodeIfPresent(Metadata.self, forKey: ._meta)
    }

    /// Encodes `uri` always; `name` and `_meta` are omitted when `nil`.
    ///
    /// - Parameter encoder: The encoder to write the value to.
    /// - Throws: An error if the underlying encoder fails.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(uri, forKey: .uri)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(_meta, forKey: ._meta)
    }
}

// MARK: -

/// The `roots/list` request. Servers send it to the client to discover which filesystem roots are exposed;
/// it carries no parameters and is answered with a ``ListRoots/Result``.
///
/// - SeeAlso: https://modelcontextprotocol.io/specification/2025-11-25/client/roots
/// - Warning: The Roots feature is deprecated by MCP `2026-07-28`. Pass directories or files
///   as tool parameters, resource URIs, or server configuration instead. See ``Deprecations``.
public enum ListRoots: Method {
    /// The JSON-RPC method name for this request: `roots/list`.
    public static let name: String = "roots/list"

    /// This method takes no parameters.
    public typealias Parameters = Empty

    /// The result returned in response to the `ListRoots` request.
    public struct Result: Hashable, Codable, Sendable {
        /// The roots the client exposes to the server.
        public let roots: [Root]
        /// Optional metadata about this result
        public var _meta: Metadata?

        /// Creates the response to a `roots/list` request.
        ///
        /// - Parameters:
        ///   - roots: The roots the client exposes; may be empty.
        ///   - _meta: Protocol-reserved result metadata. Defaults to `nil`; omitted from the wire when `nil`.
        public init(
            roots: [Root],
            _meta: Metadata? = nil
        ) {
            self.roots = roots
            self._meta = _meta
        }

        private enum CodingKeys: String, CodingKey, CaseIterable {
            case roots, _meta
        }

        /// Encodes `roots` always; `_meta` is omitted when `nil`.
        ///
        /// - Parameter encoder: The encoder to write the value to.
        /// - Throws: An error if the underlying encoder fails.
        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(roots, forKey: .roots)
            try container.encodeIfPresent(_meta, forKey: ._meta)
        }

        /// Decodes the `roots/list` result from a keyed container.
        ///
        /// Required: `roots`. Optional: `_meta`.
        ///
        /// - Parameter decoder: The decoder to read the value from.
        /// - Throws: `DecodingError` if `roots` is missing or any element is not a valid `Root`.
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            roots = try container.decode([Root].self, forKey: .roots)
            _meta = try container.decodeIfPresent(Metadata.self, forKey: ._meta)
        }
    }
}

/// The `notifications/roots/list_changed` notification. Clients that declared the `roots` capability
/// SHOULD send it whenever their list of roots changes, so servers can re-issue `roots/list`.
///
/// - SeeAlso: https://modelcontextprotocol.io/specification/2025-11-25/client/roots
public struct RootsListChangedNotification: Notification {
    /// The JSON-RPC method name for this notification: `notifications/roots/list_changed`.
    public static let name: String = "notifications/roots/list_changed"

    /// This method takes no parameters.
    public typealias Parameters = Empty
}
