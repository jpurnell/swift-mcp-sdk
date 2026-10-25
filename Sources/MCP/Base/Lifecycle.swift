/// The initialization phase MUST be the first interaction between client and server.
/// During this phase, the client and server:
/// - Establish protocol version compatibility
/// - Exchange and negotiate capabilities
/// - Share implementation details
///
/// - SeeAlso: https://spec.modelcontextprotocol.io/specification/2024-11-05/basic/lifecycle/#initialization
public enum Initialize: Method {
    /// The JSON-RPC method name, `initialize`.
    public static let name: String = "initialize"

    /// The parameters a client sends to begin initialization.
    public struct Parameters: Hashable, Codable, Sendable {
        /// The protocol version the client wants to use.
        public let protocolVersion: String
        /// The capabilities the client supports.
        public let capabilities: Client.Capabilities
        /// Name and version of the client implementation.
        public let clientInfo: Client.Info

        /// Creates initialization parameters.
        ///
        /// - Parameters:
        ///   - protocolVersion: The protocol version to request. Defaults to the latest supported.
        ///   - capabilities: The client's capabilities.
        ///   - clientInfo: Name and version of the client.
        public init(
            protocolVersion: String = Version.latest,
            capabilities: Client.Capabilities,
            clientInfo: Client.Info
        ) {
            self.protocolVersion = protocolVersion
            self.capabilities = capabilities
            self.clientInfo = clientInfo
        }

        private enum CodingKeys: String, CodingKey {
            case protocolVersion, capabilities, clientInfo
        }

        /// Decodes initialization parameters, substituting defaults for absent members.
        ///
        /// - Parameter decoder: The decoder to read from.
        /// - Throws: `DecodingError` if a present member is malformed.
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            protocolVersion =
                try container.decodeIfPresent(String.self, forKey: .protocolVersion)
                ?? Version.latest
            capabilities =
                try container.decodeIfPresent(Client.Capabilities.self, forKey: .capabilities)
                ?? .init()
            clientInfo =
                try container.decodeIfPresent(Client.Info.self, forKey: .clientInfo)
                ?? .init(name: "unknown", version: "0.0.0")
        }
    }

    /// The server's reply to initialization.
    public struct Result: Hashable, Codable, Sendable {
        /// The protocol version the server selected.
        public let protocolVersion: String
        /// The capabilities the server supports.
        public let capabilities: Server.Capabilities
        /// Name and version of the server implementation.
        public let serverInfo: Server.Info
        /// Optional instructions describing how to use the server.
        public let instructions: String?
        /// Optional protocol metadata attached to the result.
        public var _meta: Metadata?

        /// Creates an initialization result.
        ///
        /// - Parameters:
        ///   - protocolVersion: The protocol version the server selected.
        ///   - capabilities: The server's capabilities.
        ///   - serverInfo: Name and version of the server.
        ///   - instructions: Optional usage instructions for the client.
        ///   - _meta: Optional protocol metadata.
        public init(
            protocolVersion: String,
            capabilities: Server.Capabilities,
            serverInfo: Server.Info,
            instructions: String? = nil,
            _meta: Metadata? = nil
        ) {
            self.protocolVersion = protocolVersion
            self.capabilities = capabilities
            self.serverInfo = serverInfo
            self.instructions = instructions
            self._meta = _meta
        }

        private enum CodingKeys: String, CodingKey, CaseIterable {
            case protocolVersion, capabilities, serverInfo, instructions, _meta
        }

        /// Encodes the result, omitting absent optional members.
        ///
        /// - Parameter encoder: The encoder to write to.
        /// - Throws: Any error raised while encoding a member.
        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(protocolVersion, forKey: .protocolVersion)
            try container.encode(capabilities, forKey: .capabilities)
            try container.encode(serverInfo, forKey: .serverInfo)
            try container.encodeIfPresent(instructions, forKey: .instructions)
            try container.encodeIfPresent(_meta, forKey: ._meta)
        }

        /// Decodes an initialization result.
        ///
        /// - Parameter decoder: The decoder to read from.
        /// - Throws: `DecodingError` if a required member is missing or malformed.
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            protocolVersion = try container.decode(String.self, forKey: .protocolVersion)
            capabilities = try container.decode(Server.Capabilities.self, forKey: .capabilities)
            serverInfo = try container.decode(Server.Info.self, forKey: .serverInfo)
            instructions = try container.decodeIfPresent(String.self, forKey: .instructions)
            _meta = try container.decodeIfPresent(Metadata.self, forKey: ._meta)
        }
    }
}

/// After successful initialization, the client MUST send an initialized notification to indicate it is ready to begin normal operations.
/// - SeeAlso: https://spec.modelcontextprotocol.io/specification/2024-11-05/basic/lifecycle/#initialization
public struct InitializedNotification: Notification {
    /// The JSON-RPC method name, `notifications/initialized`.
    public static let name: String = "notifications/initialized"
}
