import Foundation

/// The Model Context Protocol (MCP) provides a standardized way
/// for servers to expose prompt templates to clients.
/// Prompts allow servers to provide structured messages and instructions
/// for interacting with language models.
/// Clients can discover available prompts, retrieve their contents,
/// and provide arguments to customize them.
///
/// - SeeAlso: https://modelcontextprotocol.io/specification/2025-11-25/server/prompts/
public struct Prompt: Hashable, Codable, Sendable {
    /// The prompt name
    public let name: String
    /// A human-readable prompt title
    public let title: String?
    /// The prompt description
    public let description: String?
    /// The prompt arguments
    public let arguments: [Argument]?
    /// Optional set of sized icons that the client can display in a user interface
    public var icons: [Icon]?
    /// Optional metadata about this prompt
    public var _meta: Metadata?

    /// Creates a prompt template description to advertise in a `prompts/list` result.
    ///
    /// - Parameters:
    ///   - name: Unique identifier clients pass to `prompts/get`. Required.
    ///   - title: Optional human-readable display name.
    ///   - description: Optional explanation of what the prompt does.
    ///   - arguments: Optional list of arguments the prompt accepts; `nil` means none are declared.
    ///   - icons: Optional icons a client may show in its UI.
    ///   - meta: Optional protocol metadata, stored in and encoded as `_meta`.
    public init(
        name: String,
        title: String? = nil,
        description: String? = nil,
        arguments: [Argument]? = nil,
        icons: [Icon]? = nil,
        meta: Metadata? = nil
    ) {
        self.name = name
        self.title = title
        self.description = description
        self.arguments = arguments
        self.icons = icons
        self._meta = meta
    }

    private enum CodingKeys: String, CodingKey {
        case name, title, description, arguments, icons, _meta
    }

    /// Encodes the prompt as an MCP `Prompt` object.
    ///
    /// `name` is always written. `title`, `description`, `arguments`, `icons` and `_meta` are
    /// omitted when `nil`.
    ///
    /// - Parameter encoder: The encoder to write to.
    /// - Throws: Any error thrown by the encoder or by an element's own encoding.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(arguments, forKey: .arguments)
        try container.encodeIfPresent(icons, forKey: .icons)
        try container.encodeIfPresent(_meta, forKey: ._meta)
    }

    /// Decodes a prompt from an MCP `Prompt` object.
    ///
    /// Only `name` is required; `title`, `description`, `arguments`, `icons` and `_meta` are optional
    /// and read as `nil` when absent.
    ///
    /// - Parameter decoder: The decoder to read from.
    /// - Throws: `DecodingError` if `name` is missing or any present key has the wrong type.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        arguments = try container.decodeIfPresent([Argument].self, forKey: .arguments)
        icons = try container.decodeIfPresent([Icon].self, forKey: .icons)
        _meta = try container.decodeIfPresent(Metadata.self, forKey: ._meta)
    }

    /// An argument for a prompt
    public struct Argument: Hashable, Codable, Sendable {
        /// The argument name
        public let name: String
        /// A human-readable argument title
        public let title: String?
        /// The argument description
        public let description: String?
        /// Whether the argument is required
        public let required: Bool?

        /// Creates the declaration of one argument a prompt accepts.
        ///
        /// - Parameters:
        ///   - name: The argument's key in the `arguments` dictionary of `prompts/get`. Required.
        ///   - title: Optional human-readable display name.
        ///   - description: Optional explanation of what value to supply.
        ///   - required: Whether the client must supply this argument; `nil` leaves it unspecified
        ///     (omitted from the wire) rather than asserting `false`.
        public init(
            name: String,
            title: String? = nil,
            description: String? = nil,
            required: Bool? = nil
        ) {
            self.name = name
            self.title = title
            self.description = description
            self.required = required
        }
    }

    /// A message in a prompt
    public struct Message: Hashable, Codable, Sendable {
        /// The message role
        public enum Role: String, Hashable, Codable, Sendable {
            /// A user message
            case user
            /// An assistant message
            case assistant
        }

        /// The message role
        public let role: Role
        /// The message content
        public let content: Content

        /// Creates a message from an explicit role and content.
        ///
        /// Deprecated in favor of ``user(_:)`` and ``assistant(_:)``, which state the role at the call site.
        ///
        /// - Parameters:
        ///   - role: Whether the message is from the user or the assistant.
        ///   - content: The message payload (text, image, audio, embedded resource or resource link).
        @available(
            *, deprecated, message: "Use static factory methods .user(_:) or .assistant(_:) instead"
        )
        public init(role: Role, content: Content) {
            self.role = role
            self.content = content
        }

        /// Non-deprecated initializer used by ``user(_:)`` and ``assistant(_:)`` so they do not trigger the
        /// deprecation warning on ``init(role:content:)``.
        private init(_role role: Role, _content content: Content) {
            self.role = role
            self.content = content
        }

        /// Creates a message with the `user` role.
        ///
        /// - Parameter content: The message payload. A plain string literal is accepted because
        ///   ``Content`` is `ExpressibleByStringLiteral`.
        /// - Returns: A message whose `role` is ``Role/user``.
        public static func user(_ content: Content) -> Message {
            return Message(_role: .user, _content: content)
        }

        /// Creates a message with the `assistant` role.
        ///
        /// - Parameter content: The message payload. A plain string literal is accepted because
        ///   ``Content`` is `ExpressibleByStringLiteral`.
        /// - Returns: A message whose `role` is ``Role/assistant``.
        public static func assistant(_ content: Content) -> Message {
            return Message(_role: .assistant, _content: content)
        }

        /// Content types for messages
        public enum Content: Hashable, Sendable {
            /// Text content
            case text(text: String)
            /// Image content
            case image(data: String, mimeType: String)
            /// Audio content
            case audio(data: String, mimeType: String)
            /// Embedded resource content (EmbeddedResource from spec)
            case resource(resource: Resource.Content, annotations: Resource.Annotations? = nil, _meta: Metadata? = nil)
            /// Resource link
            case resourceLink(uri: String, name: String, title: String? = nil, description: String? = nil, mimeType: String? = nil, annotations: Resource.Annotations? = nil)
        }
    }

    /// Reference type for prompts
    public struct Reference: Hashable, Codable, Sendable {
        /// The prompt reference name
        public let name: String
        /// A human-readable prompt title
        public let title: String?

        /// Creates a reference to a prompt, used as the `ref` of a `completion/complete` request.
        ///
        /// - Parameters:
        ///   - name: The name of the prompt being referenced.
        ///   - title: Optional human-readable display name.
        public init(name: String, title: String? = nil) {
            self.name = name
            self.title = title
        }

        private enum CodingKeys: String, CodingKey {
            case type, name, title
        }

        /// Encodes the reference as an MCP `PromptReference` object.
        ///
        /// Always writes `type` as the constant `"ref/prompt"` and `name`; `title` is omitted when `nil`.
        ///
        /// - Parameter encoder: The encoder to write to.
        /// - Throws: Any error thrown by the encoder.
        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("ref/prompt", forKey: .type)
            try container.encode(name, forKey: .name)
            try container.encodeIfPresent(title, forKey: .title)
        }

        /// Decodes a prompt reference from an MCP `PromptReference` object.
        ///
        /// `type` and `name` are required; `title` is optional. The value of `type` must be a string but is
        /// not checked against `"ref/prompt"`.
        ///
        /// - Parameter decoder: The decoder to read from.
        /// - Throws: `DecodingError` if `type` or `name` is missing or any key has the wrong type.
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            _ = try container.decode(String.self, forKey: .type)
            name = try container.decode(String.self, forKey: .name)
            title = try container.decodeIfPresent(String.self, forKey: .title)
        }
    }
}

// MARK: - Codable

extension Prompt.Message.Content: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, text, data, mimeType, resource, annotations, _meta
        case uri, name, title, description
    }

    /// Encodes the content as an MCP content block, discriminated by a `type` key.
    ///
    /// - `text`: `type` `"text"` and `text`.
    /// - `image` / `audio`: `type` `"image"` or `"audio"`, base64 `data` and `mimeType`.
    /// - `resource`: `type` `"resource"` and the embedded `resource`; `annotations` and `_meta` omitted when `nil`.
    /// - `resourceLink`: `type` `"resource_link"`, `uri` and `name`; `title`, `description`, `mimeType`
    ///   and `annotations` omitted when `nil`.
    ///
    /// - Parameter encoder: The encoder to write to.
    /// - Throws: Any error thrown by the encoder or by a nested value's encoding.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .image(let data, let mimeType):
            try container.encode("image", forKey: .type)
            try container.encode(data, forKey: .data)
            try container.encode(mimeType, forKey: .mimeType)
        case .audio(let data, let mimeType):
            try container.encode("audio", forKey: .type)
            try container.encode(data, forKey: .data)
            try container.encode(mimeType, forKey: .mimeType)
        case .resource(let resourceContent, let annotations, let _meta):
            try container.encode("resource", forKey: .type)
            try container.encode(resourceContent, forKey: .resource)
            try container.encodeIfPresent(annotations, forKey: .annotations)
            try container.encodeIfPresent(_meta, forKey: ._meta)
        case .resourceLink(let uri, let name, let title, let description, let mimeType, let annotations):
            try container.encode("resource_link", forKey: .type)
            try container.encode(uri, forKey: .uri)
            try container.encode(name, forKey: .name)
            try container.encodeIfPresent(title, forKey: .title)
            try container.encodeIfPresent(description, forKey: .description)
            try container.encodeIfPresent(mimeType, forKey: .mimeType)
            try container.encodeIfPresent(annotations, forKey: .annotations)
        }
    }

    /// Decodes a content block, choosing the case from its `type` key.
    ///
    /// `type` is required and must be `"text"`, `"image"`, `"audio"`, `"resource"` or `"resource_link"`.
    /// Required keys per case: `text` needs `text`; `image` and `audio` need `data` and `mimeType`;
    /// `resource` needs `resource` (`annotations` and `_meta` optional); `resource_link` needs `uri` and `name`
    /// (`title`, `description`, `mimeType`, `annotations` optional).
    ///
    /// - Parameter decoder: The decoder to read from.
    /// - Throws: `DecodingError` if a required key is missing or mistyped, or if `type` is any other value
    ///   (a data-corrupted error with the message "Unknown content type").
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "text":
            let text = try container.decode(String.self, forKey: .text)
            self = .text(text: text)
        case "image":
            let data = try container.decode(String.self, forKey: .data)
            let mimeType = try container.decode(String.self, forKey: .mimeType)
            self = .image(data: data, mimeType: mimeType)
        case "audio":
            let data = try container.decode(String.self, forKey: .data)
            let mimeType = try container.decode(String.self, forKey: .mimeType)
            self = .audio(data: data, mimeType: mimeType)
        case "resource":
            let resourceContent = try container.decode(Resource.Content.self, forKey: .resource)
            let annotations = try container.decodeIfPresent(Resource.Annotations.self, forKey: .annotations)
            let _meta = try container.decodeIfPresent(Metadata.self, forKey: ._meta)
            self = .resource(resource: resourceContent, annotations: annotations, _meta: _meta)
        case "resource_link":
            let uri = try container.decode(String.self, forKey: .uri)
            let name = try container.decode(String.self, forKey: .name)
            let title = try container.decodeIfPresent(String.self, forKey: .title)
            let description = try container.decodeIfPresent(String.self, forKey: .description)
            let mimeType = try container.decodeIfPresent(String.self, forKey: .mimeType)
            let annotations = try container.decodeIfPresent(Resource.Annotations.self, forKey: .annotations)
            self = .resourceLink(uri: uri, name: name, title: title, description: description, mimeType: mimeType, annotations: annotations)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown content type")
        }
    }
}

// MARK: - ExpressibleByStringLiteral

extension Prompt.Message.Content: ExpressibleByStringLiteral {
    /// Creates text content from a string literal, so `"Hello"` can be used wherever a ``Content`` is expected.
    ///
    /// - Parameter value: The text; the result is ``text(text:)``.
    public init(stringLiteral value: String) {
        self = .text(text: value)
    }
}

// MARK: - ExpressibleByStringInterpolation

extension Prompt.Message.Content: ExpressibleByStringInterpolation {
    /// Creates text content from an interpolated string literal, such as `"Review \(code)"`.
    ///
    /// - Parameter stringInterpolation: The interpolation buffer; the result is ``text(text:)`` of the
    ///   resolved string.
    public init(stringInterpolation: DefaultStringInterpolation) {
        self = .text(text: String(stringInterpolation: stringInterpolation))
    }
}

// MARK: -

/// To retrieve available prompts, clients send a `prompts/list` request.
/// The response is a page of ``Prompt`` descriptions plus an optional cursor for the next page.
/// - SeeAlso: https://modelcontextprotocol.io/specification/2025-11-25/server/prompts/#listing-prompts
public enum ListPrompts: Method {
    /// The JSON-RPC method name, `prompts/list`.
    public static let name: String = "prompts/list"

    /// Parameters for the `prompts/list` request.
    public struct Parameters: NotRequired, Hashable, Codable, Sendable {
        /// An opaque pagination cursor returned as `nextCursor` by a previous response; omit to start from the first page.
        public let cursor: String?

        /// Creates parameters for the first page of results (no cursor is sent).
        public init() {
            self.cursor = nil
        }

        /// Creates parameters that request a later page of results.
        ///
        /// - Parameter cursor: The opaque `nextCursor` value from a previous `prompts/list` result.
        public init(cursor: String) {
            self.cursor = cursor
        }
    }

    /// Result returned for the `prompts/list` request.
    public struct Result: Hashable, Codable, Sendable {
        /// The prompts on this page of results.
        public let prompts: [Prompt]
        /// An opaque cursor to pass as `cursor` to fetch the next page; `nil` when there are no more results.
        public let nextCursor: String?
        /// Optional protocol-reserved metadata attached to the result.
        public var _meta: Metadata?
        /// Tells the client how to parse this result.
        public var resultType: ResultType?
        /// How long, in milliseconds, the client may consider this result fresh.
        public var ttlMs: Int?
        /// Whether a shared intermediary may cache this result.
        public var cacheScope: CacheScope?

        /// Creates the response to a `prompts/list` request.
        ///
        /// - Parameters:
        ///   - prompts: The prompts on this page.
        ///   - nextCursor: Opaque cursor for the next page; `nil` when this is the last page.
        ///   - _meta: Optional protocol metadata.
        ///   - resultType: How the client should parse the result; defaults to `.complete`.
        ///   - ttlMs: Optional freshness lifetime for the result, in milliseconds.
        ///   - cacheScope: Optional hint on whether a shared intermediary may cache the result.
        public init(
            prompts: [Prompt],
            nextCursor: String? = nil,
            _meta: Metadata? = nil,
            resultType: ResultType? = .complete,
            ttlMs: Int? = nil,
            cacheScope: CacheScope? = nil
        ) {
            self.prompts = prompts
            self.nextCursor = nextCursor
            self._meta = _meta
            self.resultType = resultType
            self.ttlMs = ttlMs
            self.cacheScope = cacheScope
        }

        private enum CodingKeys: String, CodingKey, CaseIterable {
            case prompts, nextCursor, _meta, resultType, ttlMs, cacheScope
        }

        /// Encodes the `prompts/list` result.
        ///
        /// `prompts` is always written. `nextCursor`, `_meta`, `resultType`, `ttlMs` and `cacheScope` are
        /// omitted when `nil`.
        ///
        /// - Parameter encoder: The encoder to write to.
        /// - Throws: Any error thrown by the encoder.
        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(prompts, forKey: .prompts)
            try container.encodeIfPresent(nextCursor, forKey: .nextCursor)
            try container.encodeIfPresent(_meta, forKey: ._meta)
            try container.encodeIfPresent(resultType, forKey: .resultType)
            try container.encodeIfPresent(ttlMs, forKey: .ttlMs)
            try container.encodeIfPresent(cacheScope, forKey: .cacheScope)
        }

        /// Decodes a `prompts/list` result.
        ///
        /// Only `prompts` is required; `nextCursor`, `_meta`, `resultType`, `ttlMs` and `cacheScope` are optional.
        /// A `resultType` string this SDK does not recognise reads as `nil` rather than throwing.
        ///
        /// - Parameter decoder: The decoder to read from.
        /// - Throws: `DecodingError` if `prompts` is missing or any present key has the wrong type
        ///   (including an unrecognised `cacheScope`).
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            prompts = try container.decode([Prompt].self, forKey: .prompts)
            nextCursor = try container.decodeIfPresent(String.self, forKey: .nextCursor)
            _meta = try container.decodeIfPresent(Metadata.self, forKey: ._meta)
            // An unrecognised tag from a future revision reads as absent rather than
            // throwing, so the rest of the result stays readable.
            resultType = try container.decodeIfPresent(String.self, forKey: .resultType)
                .flatMap(ResultType.init(rawValue:))
            ttlMs = try container.decodeIfPresent(Int.self, forKey: .ttlMs)
            cacheScope = try container.decodeIfPresent(CacheScope.self, forKey: .cacheScope)
        }
    }
}

/// To retrieve a specific prompt, clients send a `prompts/get` request naming the prompt and supplying
/// its argument values; the response carries the rendered messages.
/// Arguments may be auto-completed through the completion API.
/// - SeeAlso: https://modelcontextprotocol.io/specification/2025-11-25/server/prompts/#getting-a-prompt
public enum GetPrompt: Method {
    /// The JSON-RPC method name, `prompts/get`.
    public static let name: String = "prompts/get"

    /// Parameters for the `prompts/get` request.
    public struct Parameters: Hashable, Codable, Sendable {
        /// The name of the item being requested.
        public let name: String
        /// Optional values for the prompt's templating arguments, keyed by argument name.
        public let arguments: [String: String]?
        /// Answers to a previous ``InputRequiredResult`` from this same request (SEP-2322).
        ///
        /// SEP-2322 is not a tools feature: any request can need input before it can answer,
        /// and `prompts/get` is where that is easiest to see — a prompt template may need to
        /// ask the user what to fill in.
        public let inputResponses: [String: InputResponse]?
        /// The opaque state from that ``InputRequiredResult``, echoed back unchanged.
        public let requestState: String?
        /// Metadata for this request.
        public let _meta: Metadata?

        /// Creates the parameters of a `prompts/get` request.
        ///
        /// - Parameters:
        ///   - name: The name of the prompt to retrieve, as advertised by `prompts/list`.
        ///   - arguments: Optional argument values keyed by argument name; all values are strings.
        ///   - inputResponses: Optional answers to a previous ``InputRequiredResult``, keyed as that result
        ///     requested. Omit on the first attempt.
        ///   - requestState: Optional opaque state from that same ``InputRequiredResult``, echoed back unchanged.
        ///   - _meta: Optional request metadata.
        public init(
            name: String,
            arguments: [String: String]? = nil,
            inputResponses: [String: InputResponse]? = nil,
            requestState: String? = nil,
            _meta: Metadata? = nil
        ) {
            self.name = name
            self.arguments = arguments
            self.inputResponses = inputResponses
            self.requestState = requestState
            self._meta = _meta
        }
    }

    /// Result returned for the `prompts/get` request.
    public struct Result: Hashable, Codable, Sendable {
        /// An optional description of the prompt's result.
        public let description: String?
        /// The messages that make up the prompt.
        public let messages: [Prompt.Message]
        /// Optional metadata about this result
        public var _meta: Metadata?
        /// Tells the client how to parse this result.
        public var resultType: ResultType?

        /// Creates the response to a `prompts/get` request.
        ///
        /// - Parameters:
        ///   - description: Optional description of the rendered prompt.
        ///   - messages: The messages that make up the prompt, in order.
        ///   - _meta: Optional protocol metadata.
        ///   - resultType: How the client should parse the result; defaults to `.complete`.
        public init(
            description: String? = nil,
            messages: [Prompt.Message],
            _meta: Metadata? = nil,
            resultType: ResultType? = .complete
        ) {
            self.description = description
            self.messages = messages
            self._meta = _meta
            self.resultType = resultType
        }

        private enum CodingKeys: String, CodingKey, CaseIterable {
            case description, messages, _meta, resultType
        }

        /// Encodes the `prompts/get` result.
        ///
        /// `messages` is always written. `description`, `_meta` and `resultType` are omitted when `nil`.
        ///
        /// - Parameter encoder: The encoder to write to.
        /// - Throws: Any error thrown by the encoder.
        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(description, forKey: .description)
            try container.encode(messages, forKey: .messages)
            try container.encodeIfPresent(_meta, forKey: ._meta)
            try container.encodeIfPresent(resultType, forKey: .resultType)
        }

        /// Decodes a `prompts/get` result.
        ///
        /// Only `messages` is required; `description`, `_meta` and `resultType` are optional. A `resultType`
        /// string this SDK does not recognise reads as `nil` rather than throwing.
        ///
        /// - Parameter decoder: The decoder to read from.
        /// - Throws: `DecodingError` if `messages` is missing or any present key has the wrong type.
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            description = try container.decodeIfPresent(String.self, forKey: .description)
            messages = try container.decode([Prompt.Message].self, forKey: .messages)
            _meta = try container.decodeIfPresent(Metadata.self, forKey: ._meta)
            // An unrecognised tag from a future revision reads as absent rather than
            // throwing, so the rest of the result stays readable.
            resultType = try container.decodeIfPresent(String.self, forKey: .resultType)
                .flatMap(ResultType.init(rawValue:))
        }
    }
}

/// When the list of available prompts changes, servers that declared the listChanged capability SHOULD send a notification.
/// - SeeAlso: https://modelcontextprotocol.io/specification/2025-11-25/server/prompts/#list-changed-notification
public struct PromptListChangedNotification: Notification {
    /// The JSON-RPC notification name, `notifications/prompts/list_changed`.
    public static let name: String = "notifications/prompts/list_changed"
}
