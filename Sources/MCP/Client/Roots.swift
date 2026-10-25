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
    /// The root URI (must use file:// scheme)
    public let uri: String
    /// Optional human-readable name for the root
    public let name: String?
    /// Optional metadata
    public var _meta: Metadata?

    /// Creates a new `Root`.
    ///
    /// - Parameters:
    ///   - uri: The root URI (must use file:// scheme)
    ///   - name: Optional human-readable name for the root
    ///   - _meta: Optional metadata
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

    /// Creates an instance by decoding from the given decoder.
    ///
    /// - Parameter decoder: The decoder to read the value from.
    /// - Throws: `DecodingError` if the data is missing or malformed.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        uri = try container.decode(String.self, forKey: .uri)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        _meta = try container.decodeIfPresent(Metadata.self, forKey: ._meta)
    }

    /// Encodes this value into the given encoder.
    ///
    /// - Parameter encoder: The encoder to write the value to.
    /// - Throws: An error if encoding fails.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(uri, forKey: .uri)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(_meta, forKey: ._meta)
    }
}

// MARK: -

/// To discover available roots, servers send a `roots/list` request to the client.
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

        /// Creates a new `Result`.
        ///
        /// - Parameters:
        ///   - roots: The roots the client exposes.
        ///   - _meta: Optional metadata about this result
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

        /// Encodes this value into the given encoder.
        ///
        /// - Parameter encoder: The encoder to write the value to.
        /// - Throws: An error if encoding fails.
        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(roots, forKey: .roots)
            try container.encodeIfPresent(_meta, forKey: ._meta)
        }

        /// Creates an instance by decoding from the given decoder.
        ///
        /// - Parameter decoder: The decoder to read the value from.
        /// - Throws: `DecodingError` if the data is missing or malformed.
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            roots = try container.decode([Root].self, forKey: .roots)
            _meta = try container.decodeIfPresent(Metadata.self, forKey: ._meta)
        }
    }
}

/// When the list of roots changes, clients that declared the `roots` capability
/// SHOULD send this notification to inform servers.
/// - SeeAlso: https://modelcontextprotocol.io/specification/2025-11-25/client/roots
public struct RootsListChangedNotification: Notification {
    /// The JSON-RPC method name for this notification: `notifications/roots/list_changed`.
    public static let name: String = "notifications/roots/list_changed"

    /// This method takes no parameters.
    public typealias Parameters = Empty
}
