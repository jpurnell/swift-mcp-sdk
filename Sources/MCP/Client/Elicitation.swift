import Foundation

/// Types supporting the MCP elicitation flow.
///
/// Servers use elicitation to collect structured input from users via the client.
/// The schema subset mirrors the 2025-11-25 revision of the specification.
public enum Elicitation {
    /// Schema describing the expected response content.
    public struct RequestSchema: Hashable, Codable, Sendable {
        /// Supported top-level types. Currently limited to objects.
        public enum SchemaType: String, Hashable, Codable, Sendable {
            /// A JSON Schema `object` (wire value `"object"`).
            case object
        }

        /// Schema title presented to users.
        public var title: String?
        /// Schema description providing additional guidance.
        public var description: String?
        /// Raw JSON Schema fragments describing the requested fields.
        public var properties: [String: Value]
        /// List of required field keys.
        public var required: [String]?
        /// Top-level schema type. Defaults to `object`.
        public var type: SchemaType

        /// Creates the schema describing the form fields a server wants the user to fill in.
        ///
        /// - Parameters:
        ///   - title: Optional title shown to the user. Defaults to `nil`.
        ///   - description: Optional guidance text. Defaults to `nil`.
        ///   - properties: Field name to JSON Schema fragment (e.g. `.object(["type": .string("string")])`).
        ///     Defaults to empty.
        ///   - required: Names from `properties` the user must supply. Defaults to `nil` (none required).
        ///   - type: Top-level schema type; only `.object` exists. Defaults to `.object`.
        public init(
            title: String? = nil,
            description: String? = nil,
            properties: [String: Value] = [:],
            required: [String]? = nil,
            type: SchemaType = .object
        ) {
            self.title = title
            self.description = description
            self.properties = properties
            self.required = required
            self.type = type
        }

        private enum CodingKeys: String, CodingKey {
            case title, description, properties, required, type
        }
    }

    /// Elicitation mode indicating how user input is collected
    public enum Mode: String, Hashable, Codable, Sendable {
        /// Form-based elicitation (client displays UI)
        case form
        /// URL-based elicitation (client opens external URL)
        case url
    }
}

/// The `elicitation/create` request. A server sends it to ask the client to collect input from the user,
/// either through a form described by a schema or by sending the user to a URL. The client answers with a
/// ``CreateElicitation/Result``.
///
/// - SeeAlso: https://modelcontextprotocol.io/specification/2025-06-18/client/elicitation
public enum CreateElicitation: Method {
    /// The JSON-RPC method name for this request: `elicitation/create`.
    public static let name = "elicitation/create"

    /// Parameters for the `CreateElicitation` request.
    public enum Parameters: Hashable, Sendable {
        /// Form-based elicitation parameters
        case form(FormParameters)
        /// URL-based elicitation parameters
        case url(URLParameters)

        /// Parameters for form-based elicitation
        public struct FormParameters: Hashable, Codable, Sendable {
            /// Message displayed to the user describing the request
            public var message: String
            /// Elicitation mode (optional for backward compatibility, defaults to form)
            public var mode: Elicitation.Mode?
            /// Schema describing the expected response content (required per spec)
            public var requestedSchema: Elicitation.RequestSchema
            /// Optional metadata
            public var _meta: Metadata?

            /// Creates parameters for a form-mode `elicitation/create` request.
            ///
            /// - Parameters:
            ///   - message: Prompt shown to the user explaining what is being requested.
            ///   - mode: Explicit `.form` marker. Defaults to `nil`, which omits `mode` from the wire (peers
            ///     treat a missing mode as form).
            ///   - requestedSchema: Schema of the fields to collect. Defaults to an empty object schema.
            ///   - _meta: Protocol-reserved metadata. Defaults to `nil`.
            public init(
                message: String,
                mode: Elicitation.Mode? = nil,
                requestedSchema: Elicitation.RequestSchema = .init(),
                _meta: Metadata? = nil
            ) {
                self.message = message
                self.mode = mode
                self.requestedSchema = requestedSchema
                self._meta = _meta
            }
        }

        /// Parameters for URL-based elicitation
        public struct URLParameters: Hashable, Codable, Sendable {
            /// Message displayed to the user describing the request
            public var message: String
            /// Elicitation mode (always "url")
            public var mode: Elicitation.Mode
            /// URL for the user to visit
            public var url: String
            /// Unique identifier for this elicitation
            public var elicitationId: String
            /// Optional metadata
            public var _meta: Metadata?

            /// Creates parameters for a URL-mode `elicitation/create` request, in which the client sends the
            /// user to an external page. `mode` is fixed to `.url`.
            ///
            /// - Parameters:
            ///   - message: Prompt shown to the user explaining why they are being sent to the URL.
            ///   - url: The absolute URL the user should open, as a string; not validated.
            ///   - elicitationId: Server-chosen identifier that later correlates an
            ///     ``ElicitationCompleteNotification`` with this request.
            ///   - _meta: Protocol-reserved metadata. Defaults to `nil`.
            public init(
                message: String,
                url: String,
                elicitationId: String,
                _meta: Metadata? = nil
            ) {
                self.message = message
                self.mode = .url
                self.url = url
                self.elicitationId = elicitationId
                self._meta = _meta
            }
        }
    }

    /// The result returned in response to the `CreateElicitation` request.
    public struct Result: Hashable, Codable, Sendable {
        /// Indicates how the user responded to the request.
        public enum Action: String, Hashable, Codable, Sendable {
            /// The user submitted the form or completed the flow.
            case accept
            /// The user explicitly refused to provide the information.
            case decline
            /// The user dismissed the request without choosing.
            case cancel
        }

        /// Selected action.
        public var action: Action
        /// Submitted content when action is `.accept`.
        public var content: [String: Value]?
        /// Optional metadata about this result
        public var _meta: Metadata?

        /// Creates the client's response to an `elicitation/create` request.
        ///
        /// - Parameters:
        ///   - action: How the user responded: accepted, declined, or dismissed.
        ///   - content: The submitted field values keyed by property name; meaningful only for `.accept`.
        ///     Defaults to `nil`; omitted from the wire when `nil`.
        ///   - _meta: Protocol-reserved result metadata. Defaults to `nil`.
        public init(
            action: Action,
            content: [String: Value]? = nil,
            _meta: Metadata? = nil
        ) {
            self.action = action
            self.content = content
            self._meta = _meta
        }

        private enum CodingKeys: String, CodingKey, CaseIterable {
            case action, content, _meta
        }

        /// Encodes `action` always; `content` and `_meta` are omitted when `nil`.
        ///
        /// - Parameter encoder: The encoder to write the value to.
        /// - Throws: An error if the underlying encoder fails.
        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(action, forKey: .action)
            try container.encodeIfPresent(content, forKey: .content)
            try container.encodeIfPresent(_meta, forKey: ._meta)
        }

        /// Decodes the user's response from a keyed container.
        ///
        /// Required: `action`. Optional: `content`, `_meta`.
        ///
        /// - Parameter decoder: The decoder to read the value from.
        /// - Throws: `DecodingError` if `action` is missing or not one of `accept`, `decline`, `cancel`, or if
        ///   `content` is not an object of valid `Value`s.
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            action = try container.decode(Action.self, forKey: .action)
            content = try container.decodeIfPresent([String: Value].self, forKey: .content)
            _meta = try container.decodeIfPresent(Metadata.self, forKey: ._meta)
        }
    }
}

// MARK: - Codable

extension CreateElicitation.Parameters: Codable {
    private enum CodingKeys: String, CodingKey {
        case mode, message, requestedSchema, url, elicitationId
        case _meta
    }

    /// Decodes elicitation parameters, choosing the variant from the `mode` key.
    ///
    /// `mode == "url"` decodes `.url`, requiring `message`, `url` and `elicitationId`. Any other case (absent,
    /// `"form"`) decodes `.form`, requiring `message` and `requestedSchema`. `_meta` is optional in both.
    ///
    /// - Parameter decoder: The decoder to read the value from.
    /// - Throws: `DecodingError` if `mode` is present but not a known mode, or a key required by the chosen
    ///   variant is missing or malformed.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Read mode field (may be missing for backward compatibility)
        let mode = try container.decodeIfPresent(Elicitation.Mode.self, forKey: .mode)

        // Discriminate based on mode
        if mode == .url {
            // URL mode
            let message = try container.decode(String.self, forKey: .message)
            let url = try container.decode(String.self, forKey: .url)
            let elicitationId = try container.decode(String.self, forKey: .elicitationId)
            let _meta = try container.decodeIfPresent(Metadata.self, forKey: ._meta)
            self = .url(URLParameters(
                message: message,
                url: url,
                elicitationId: elicitationId,
                _meta: _meta))
        } else {
            // Form mode (default for backward compatibility)
            let message = try container.decode(String.self, forKey: .message)
            let requestedSchema = try container.decode(
                Elicitation.RequestSchema.self, forKey: .requestedSchema)
            let _meta = try container.decodeIfPresent(Metadata.self, forKey: ._meta)
            self = .form(FormParameters(
                message: message,
                mode: mode,
                requestedSchema: requestedSchema,
                _meta: _meta))
        }
    }

    /// Encodes the active variant as a flat object.
    ///
    /// `.form` writes `message`, `mode` (only if set), `requestedSchema` and `_meta` (if set). `.url` writes
    /// `message`, `mode` (always `"url"`), `url`, `elicitationId` and `_meta` (if set).
    ///
    /// - Parameter encoder: The encoder to write the value to.
    /// - Throws: An error if the underlying encoder fails.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .form(let params):
            try container.encode(params.message, forKey: .message)
            try container.encodeIfPresent(params.mode, forKey: .mode)
            try container.encodeIfPresent(params.requestedSchema, forKey: .requestedSchema)
            try container.encodeIfPresent(params._meta, forKey: ._meta)
        case .url(let params):
            try container.encode(params.message, forKey: .message)
            try container.encode(params.mode, forKey: .mode)
            try container.encode(params.url, forKey: .url)
            try container.encode(params.elicitationId, forKey: .elicitationId)
            try container.encodeIfPresent(params._meta, forKey: ._meta)
        }
    }
}

/// The `notifications/elicitation/complete` notification, sent by the server to tell the client that a
/// URL-mode elicitation (identified by its `elicitationId`) has finished out of band.
public struct ElicitationCompleteNotification: Notification {
    /// The JSON-RPC method name for this notification: `notifications/elicitation/complete`.
    public static let name = "notifications/elicitation/complete"

    /// Parameters for the `ElicitationCompleteNotification` notification.
    public struct Parameters: Hashable, Codable, Sendable {
        /// The elicitation ID that was completed
        public var elicitationId: String

        /// Creates the parameters for an elicitation-complete notification.
        ///
        /// - Parameters:
        ///   - elicitationId: The `elicitationId` of the URL-mode request that has completed.
        public init(elicitationId: String) {
            self.elicitationId = elicitationId
        }
    }
}
