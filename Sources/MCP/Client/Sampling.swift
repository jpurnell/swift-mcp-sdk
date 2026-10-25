import Foundation

/// The Model Context Protocol (MCP) allows servers to request LLM completions
/// through the client, enabling sophisticated agentic behaviors while maintaining
/// security and privacy.
///
/// - SeeAlso: https://modelcontextprotocol.io/docs/concepts/sampling#how-sampling-works
public enum Sampling {
    /// A message in the conversation history.
    public struct Message: Hashable, Sendable {
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
        /// Optional metadata
        public var _meta: Metadata?

        /// Creates a message with an explicit role.
        ///
        /// Deprecated in favor of ``user(_:_meta:)`` and ``assistant(_:_meta:)``.
        ///
        /// - Parameters:
        ///   - role: Whether the message is from the user or the assistant.
        ///   - content: The message body, a single block or several.
        ///   - _meta: Protocol-reserved metadata. Defaults to `nil`.
        @available(
            *, deprecated, message: "Use static factory methods .user(_:) or .assistant(_:) instead"
        )
        public init(role: Role, content: Content, _meta: Metadata? = nil) {
            self.role = role
            self.content = content
            self._meta = _meta
        }

        /// Private initializer for convenience methods to avoid deprecation warnings
        private init(_role role: Role, _content content: Content, _meta: Metadata? = nil) {
            self.role = role
            self.content = content
            self._meta = _meta
        }

        /// Creates a message with the `user` role.
        ///
        /// - Parameters:
        ///   - content: The message body, a single block or several.
        ///   - _meta: Protocol-reserved metadata. Defaults to `nil`.
        /// - Returns: A message whose `role` is `.user`.
        public static func user(_ content: Content, _meta: Metadata? = nil) -> Message {
            return Message(_role: .user, _content: content, _meta: _meta)
        }

        /// Creates a message with the `assistant` role.
        ///
        /// - Parameters:
        ///   - content: The message body, a single block or several.
        ///   - _meta: Protocol-reserved metadata. Defaults to `nil`.
        /// - Returns: A message whose `role` is `.assistant`.
        public static func assistant(_ content: Content, _meta: Metadata? = nil) -> Message {
            return Message(_role: .assistant, _content: content, _meta: _meta)
        }

        /// Content types for sampling messages
        public enum Content: Hashable, Sendable {
            /// Single content block
            case single(ContentBlock)
            /// Multiple content blocks
            case multiple([ContentBlock])

            /// Individual content blocks in messages
            public enum ContentBlock: Hashable, Sendable {
                /// Text content
                case text(String)
                /// Image content
                case image(data: String, mimeType: String)
                /// Audio content
                case audio(data: String, mimeType: String)
                /// Tool use content
                case toolUse(Sampling.ToolUseContent)
                /// Tool result content
                case toolResult(Sampling.ToolResultContent)
            }

            /// Returns true if this is a single content block
            public var isSingle: Bool {
                if case .single = self { return true }
                return false
            }

            /// Returns content as an array of blocks
            public var asArray: [ContentBlock] {
                switch self {
                case .single(let block):
                    return [block]
                case .multiple(let blocks):
                    return blocks
                }
            }

            /// Creates single-block text content.
            ///
            /// - Parameter text: The text of the block.
            public static func text(_ text: String) -> Content {
                .single(.text(text))
            }

            /// Creates single-block image content.
            ///
            /// - Parameters:
            ///   - data: Base64-encoded image bytes.
            ///   - mimeType: The image's MIME type, e.g. `image/png`.
            public static func image(data: String, mimeType: String) -> Content {
                .single(.image(data: data, mimeType: mimeType))
            }

            /// Creates single-block audio content.
            ///
            /// - Parameters:
            ///   - data: Base64-encoded audio bytes.
            ///   - mimeType: The audio's MIME type, e.g. `audio/wav`.
            public static func audio(data: String, mimeType: String) -> Content {
                .single(.audio(data: data, mimeType: mimeType))
            }
        }
    }

    /// Model preferences for sampling requests
    public struct ModelPreferences: Hashable, Codable, Sendable {
        /// Model hints for selection
        public struct Hint: Hashable, Codable, Sendable {
            /// Suggested model name/family
            public let name: String?

            /// Creates a model-name hint for ``ModelPreferences``.
            ///
            /// - Parameters:
            ///   - name: A model name or family substring (e.g. `claude-sonnet`) the client may match against
            ///     its available models. Defaults to `nil`.
            public init(name: String? = nil) {
                self.name = name
            }
        }

        /// Array of model name suggestions that clients can use to select an appropriate model
        public let hints: [Hint]?
        /// Importance of minimizing costs (0-1 normalized)
        public let costPriority: UnitInterval?
        /// Importance of low latency response (0-1 normalized)
        public let speedPriority: UnitInterval?
        /// Importance of advanced model capabilities (0-1 normalized)
        public let intelligencePriority: UnitInterval?

        /// Creates the model-selection preferences a server attaches to a sampling request. These are advisory;
        /// the client makes the final model choice.
        ///
        /// - Parameters:
        ///   - hints: Model-name suggestions in order of preference. Defaults to `nil`.
        ///   - costPriority: How much to favor cheaper models, as a `UnitInterval` in 0...1. Defaults to `nil`.
        ///   - speedPriority: How much to favor low latency, 0...1. Defaults to `nil`.
        ///   - intelligencePriority: How much to favor capable models, 0...1. Defaults to `nil`.
        public init(
            hints: [Hint]? = nil,
            costPriority: UnitInterval? = nil,
            speedPriority: UnitInterval? = nil,
            intelligencePriority: UnitInterval? = nil
        ) {
            self.hints = hints
            self.costPriority = costPriority
            self.speedPriority = speedPriority
            self.intelligencePriority = intelligencePriority
        }
    }

    /// Context inclusion options for sampling requests
    public enum ContextInclusion: String, Hashable, Codable, Sendable {
        /// No additional context
        case none
        /// Include context from the requesting server.
        ///
        /// - Warning: Deprecated by MCP `2026-07-28`. Omit `includeContext` or use ``none``.
        case thisServer
        /// Include context from all connected MCP servers.
        ///
        /// - Warning: Deprecated by MCP `2026-07-28`. Omit `includeContext` or use ``none``.
        case allServers
    }

    /// Stop reason for sampling completion.
    ///
    /// The spec defines this as an open string — any provider-specific value is valid.
    /// The well-known values are exposed as static constants.
    public struct StopReason: RawRepresentable, Hashable, Codable, Sendable,
        ExpressibleByStringLiteral
    {
        /// The stop reason string as sent on the wire.
        public let rawValue: String
        /// Creates a stop reason from its wire string (the `RawRepresentable` initializer).
        ///
        /// - Parameter rawValue: The stop reason string. Any provider-specific value is valid.
        public init(rawValue: String) { self.rawValue = rawValue }
        /// Creates a stop reason from a string literal.
        ///
        /// - Parameter value: The stop reason string.
        public init(stringLiteral value: String) { self.rawValue = value }

        /// Natural end of turn
        public static let endTurn = StopReason(rawValue: "endTurn")
        /// Hit a stop sequence
        public static let stopSequence = StopReason(rawValue: "stopSequence")
        /// Reached maximum tokens
        public static let maxTokens = StopReason(rawValue: "maxTokens")
        /// Model wants to use a tool
        public static let toolUse = StopReason(rawValue: "toolUse")
    }

    /// Content representing a tool use request from the model
    public struct ToolUseContent: Hashable, Codable, Sendable {
        /// Unique identifier for this tool use
        public let id: String
        /// Name of the tool being invoked
        public let name: String
        /// Input parameters for the tool
        public let input: [String: Value]
        /// Optional metadata
        public var _meta: Metadata?

        /// Creates a record of the model requesting a tool call.
        ///
        /// - Parameters:
        ///   - id: Identifier for this call; a later ``Sampling/ToolResultContent`` echoes it as `toolUseId`.
        ///   - name: The name of the tool the model wants to invoke.
        ///   - input: The arguments for the tool, keyed by parameter name.
        ///   - _meta: Protocol-reserved metadata. Defaults to `nil`.
        public init(id: String, name: String, input: [String: Value], _meta: Metadata? = nil) {
            self.id = id
            self.name = name
            self.input = input
            self._meta = _meta
        }
    }

    /// Content representing the result of a tool execution
    public struct ToolResultContent: Hashable, Codable, Sendable {
        /// ID of the tool use this result corresponds to
        public let toolUseId: String
        /// Content blocks from tool execution
        public let content: [ContentBlock]
        /// Structured data from tool execution
        public let structuredContent: [String: Value]?
        /// Whether the tool execution resulted in an error
        public let isError: Bool?
        /// Optional metadata
        public var _meta: Metadata?

        /// Individual content blocks in tool results
        public enum ContentBlock: Hashable, Sendable {
            /// Text content
            case text(String)
            /// Image content
            case image(data: String, mimeType: String)
            /// Audio content
            case audio(data: String, mimeType: String)
            /// Embedded resource content
            case resource(resource: Resource.Content, annotations: Resource.Annotations?, _meta: Metadata?)
            /// Resource link
            case resourceLink(uri: String, name: String, title: String?, description: String?, mimeType: String?, annotations: Resource.Annotations?)
        }

        /// Creates the outcome of a tool call to feed back to the model.
        ///
        /// - Parameters:
        ///   - toolUseId: The `id` of the ``Sampling/ToolUseContent`` this answers.
        ///   - content: The tool's output blocks (text, image, audio, resource, or resource link).
        ///   - structuredContent: Optional structured output as a JSON object. Defaults to `nil`.
        ///   - isError: `true` if the tool failed. Defaults to `nil` (unspecified).
        ///   - _meta: Protocol-reserved metadata. Defaults to `nil`.
        public init(
            toolUseId: String,
            content: [ContentBlock],
            structuredContent: [String: Value]? = nil,
            isError: Bool? = nil,
            _meta: Metadata? = nil
        ) {
            self.toolUseId = toolUseId
            self.content = content
            self.structuredContent = structuredContent
            self.isError = isError
            self._meta = _meta
        }
    }
}

// MARK: - Codable

extension Sampling.Message: Codable {
    private enum CodingKeys: String, CodingKey {
        case role, content, _meta
    }

    /// Decodes a message from a keyed container.
    ///
    /// Required: `role` (`user` or `assistant`) and `content` (a single block or an array of blocks).
    /// Optional: `_meta`.
    ///
    /// - Parameter decoder: The decoder to read the value from.
    /// - Throws: `DecodingError` if a required key is missing or malformed.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        role = try container.decode(Role.self, forKey: .role)
        content = try container.decode(Content.self, forKey: .content)
        _meta = try container.decodeIfPresent(Metadata.self, forKey: ._meta)
    }

    /// Encodes `role` and `content` always; `_meta` is omitted when `nil`.
    ///
    /// - Parameter encoder: The encoder to write the value to.
    /// - Throws: An error if the underlying encoder fails.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(role, forKey: .role)
        try container.encode(content, forKey: .content)
        try container.encodeIfPresent(_meta, forKey: ._meta)
    }
}

extension Sampling.Message.Content.ContentBlock: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, text, data, mimeType
        case id, name, input, _meta
        case toolUseId, content, structuredContent, isError
    }

    /// Decodes one content block, using the `type` key as discriminator.
    ///
    /// Recognised types: `text`, `image`, `audio`, `tool_use`, `tool_result`. Required keys per type: `text`
    /// (`text`); `image`/`audio` (`data`, `mimeType`); `tool_use` (`id`, `name`, `input`); `tool_result`
    /// (`toolUseId`, `content`). `_meta` is optional on `tool_use`; `structuredContent`, `isError` and `_meta`
    /// are optional on `tool_result`.
    ///
    /// - Parameter decoder: The decoder to read the value from.
    /// - Throws: `DecodingError` if `type` is missing, `DecodingError.dataCorrupted` if it is not a recognised
    ///   type, or a key required by that type is missing or malformed.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "text":
            let text = try container.decode(String.self, forKey: .text)
            self = .text(text)
        case "image":
            let data = try container.decode(String.self, forKey: .data)
            let mimeType = try container.decode(String.self, forKey: .mimeType)
            self = .image(data: data, mimeType: mimeType)
        case "audio":
            let data = try container.decode(String.self, forKey: .data)
            let mimeType = try container.decode(String.self, forKey: .mimeType)
            self = .audio(data: data, mimeType: mimeType)
        case "tool_use":
            let id = try container.decode(String.self, forKey: .id)
            let name = try container.decode(String.self, forKey: .name)
            let input = try container.decode([String: Value].self, forKey: .input)
            let _meta = try container.decodeIfPresent(Metadata.self, forKey: ._meta)
            self = .toolUse(Sampling.ToolUseContent(id: id, name: name, input: input, _meta: _meta))
        case "tool_result":
            let toolUseId = try container.decode(String.self, forKey: .toolUseId)
            let content = try container.decode([Sampling.ToolResultContent.ContentBlock].self, forKey: .content)
            let structuredContent = try container.decodeIfPresent([String: Value].self, forKey: .structuredContent)
            let isError = try container.decodeIfPresent(Bool.self, forKey: .isError)
            let _meta = try container.decodeIfPresent(Metadata.self, forKey: ._meta)
            self = .toolResult(Sampling.ToolResultContent(
                toolUseId: toolUseId,
                content: content,
                structuredContent: structuredContent,
                isError: isError,
                _meta: _meta))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: container,
                debugDescription: "Unknown sampling message content block type")
        }
    }

    /// Encodes the block as a flat object with a `type` discriminator.
    ///
    /// Wire types are `text`, `image`, `audio`, `tool_use` (note the underscore) and `tool_result`. Optional
    /// `_meta` (on `tool_use` and `tool_result`), `structuredContent` and `isError` are omitted when `nil`.
    ///
    /// - Parameter encoder: The encoder to write the value to.
    /// - Throws: An error if the underlying encoder fails.
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
        case .toolUse(let toolUse):
            try container.encode("tool_use", forKey: .type)
            try container.encode(toolUse.id, forKey: .id)
            try container.encode(toolUse.name, forKey: .name)
            try container.encode(toolUse.input, forKey: .input)
            try container.encodeIfPresent(toolUse._meta, forKey: ._meta)
        case .toolResult(let toolResult):
            try container.encode("tool_result", forKey: .type)
            try container.encode(toolResult.toolUseId, forKey: .toolUseId)
            try container.encode(toolResult.content, forKey: .content)
            try container.encodeIfPresent(toolResult.structuredContent, forKey: .structuredContent)
            try container.encodeIfPresent(toolResult.isError, forKey: .isError)
            try container.encodeIfPresent(toolResult._meta, forKey: ._meta)
        }
    }
}

extension Sampling.Message.Content: Codable {
    /// Creates content by decoding either a single content block or an array of blocks.
    ///
    /// A single-element array is unwrapped to a single block.
    ///
    /// - Parameter decoder: The decoder to read the value from.
    /// - Throws: `DecodingError` if the data is neither a content block nor an array of them.
    public init(from decoder: Decoder) throws {
        // Try to decode as an array first
        switch Result(catching: { try [ContentBlock](from: decoder) }) {
        case .success(let blocks):
            // If it's a single-element array, unwrap it to single
            if blocks.count == 1, let block = blocks.first {
                self = .single(block)
            } else {
                self = .multiple(blocks)
            }
        case .failure:
            // Not an array: decode as a single block. A malformed single block throws
            // its own error here, so nothing is lost by moving on from the array probe.
            let block = try ContentBlock(from: decoder)
            self = .single(block)
        }
    }

    /// Encodes this content into the given encoder.
    ///
    /// A single block is encoded directly, not wrapped in an array; multiple blocks are encoded as an array.
    ///
    /// - Parameter encoder: The encoder to write the value to.
    /// - Throws: An error if encoding fails.
    public func encode(to encoder: Encoder) throws {
        switch self {
        case .single(let block):
            // Encode single block directly (not as array)
            try block.encode(to: encoder)
        case .multiple(let blocks):
            // Encode as array
            try blocks.encode(to: encoder)
        }
    }
}

// MARK: - ExpressibleByStringLiteral

extension Sampling.Message.Content: ExpressibleByStringLiteral {
    /// Creates single text content from a string literal.
    ///
    /// - Parameter value: The text of the content.
    public init(stringLiteral value: String) {
        self = .single(.text(value))
    }
}

// MARK: - ExpressibleByStringInterpolation

extension Sampling.Message.Content: ExpressibleByStringInterpolation {
    /// Creates single text content from a string interpolation.
    ///
    /// - Parameter stringInterpolation: The interpolated text.
    public init(stringInterpolation: DefaultStringInterpolation) {
        self = .single(.text(String(stringInterpolation: stringInterpolation)))
    }
}

extension Sampling.ToolResultContent.ContentBlock: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, text, data, mimeType, resource, annotations, _meta
        case uri, name, title, description
    }

    /// Decodes one tool-result content block, using the `type` key as discriminator.
    ///
    /// Recognised types: `text`, `image`, `audio`, `resource` (`resource`; optional `annotations`, `_meta`) and
    /// `resource_link` (`uri`, `name`; optional `title`, `description`, `mimeType`, `annotations`).
    ///
    /// - Parameter decoder: The decoder to read the value from.
    /// - Throws: `DecodingError` if `type` is missing, `DecodingError.dataCorrupted` if it is not a recognised
    ///   type, or a key required by that type is missing or malformed.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "text":
            let text = try container.decode(String.self, forKey: .text)
            self = .text(text)
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
            self = .resourceLink(
                uri: uri, name: name, title: title, description: description,
                mimeType: mimeType, annotations: annotations)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: container,
                debugDescription: "Unknown tool result content block type")
        }
    }

    /// Encodes the block as a flat object with a `type` discriminator (`text`, `image`, `audio`, `resource`,
    /// `resource_link`). Optional fields are omitted when `nil`. A `resource_link` writes no `_meta`.
    ///
    /// - Parameter encoder: The encoder to write the value to.
    /// - Throws: An error if the underlying encoder fails.
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
}

// MARK: -

/// The `sampling/createMessage` request. A server sends it to ask the client to generate an LLM completion
/// from the supplied messages; the client answers with a ``CreateSamplingMessage/Result``.
///
/// - SeeAlso: https://modelcontextprotocol.io/docs/concepts/sampling#how-sampling-works
/// - Warning: The Sampling feature is deprecated by MCP `2026-07-28`. Integrate directly with
///   an LLM provider's API instead. See ``Deprecations``.
public enum CreateSamplingMessage: Method {
    /// The JSON-RPC method name for this request: `sampling/createMessage`.
    public static let name = "sampling/createMessage"

    /// Tool choice configuration for sampling
    public struct ToolChoice: Hashable, Codable, Sendable {
        /// Tool choice mode
        public enum Mode: String, Hashable, Codable, Sendable {
            /// Automatically decide whether to use tools
            case auto
            /// Require using at least one tool
            case required
            /// Do not use any tools
            case none
        }

        /// The tool choice mode. If omitted, defaults to `.auto`.
        public let mode: Mode?

        /// Creates a tool-choice setting for a sampling request.
        ///
        /// - Parameters:
        ///   - mode: Whether the model may (`.auto`), must (`.required`) or must not (`.none`) call tools.
        ///     Defaults to `.auto`; `nil` is treated the same on the wire.
        public init(mode: Mode? = .auto) {
            self.mode = mode
        }

        private enum CodingKeys: String, CodingKey {
            case mode
        }

        /// Decodes tool choice from a keyed container.
        ///
        /// `mode` is optional; when absent the result's `mode` is `.auto`.
        ///
        /// - Parameter decoder: The decoder to read the value from.
        /// - Throws: `DecodingError` if `mode` is present but not `auto`, `required` or `none`.
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            mode = try container.decodeIfPresent(Mode.self, forKey: .mode) ?? .auto
        }

        /// Encodes `mode` only when it is non-nil and not `.auto`, so `.auto` and `nil` both produce an empty
        /// object (the spec default).
        ///
        /// - Parameter encoder: The encoder to write the value to.
        /// - Throws: An error if the underlying encoder fails.
        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            if let mode, mode != .auto {
                try container.encode(mode, forKey: .mode)
            }
        }
    }

    /// Parameters for the `CreateSamplingMessage` request.
    public struct Parameters: Hashable, Codable, Sendable {
        /// The conversation history to send to the LLM
        public let messages: [Sampling.Message]
        /// Model selection preferences
        public let modelPreferences: Sampling.ModelPreferences?
        /// Optional system prompt
        public let systemPrompt: String?
        /// What MCP context to include
        public let includeContext: Sampling.ContextInclusion?
        /// Controls randomness (0.0 to 1.0)
        public let temperature: Double?
        /// Maximum tokens to generate
        public let maxTokens: Int
        /// Array of sequences that stop generation
        public let stopSequences: [String]?
        /// Optional request metadata
        public var _meta: Metadata?
        /// Tools available for the model to use
        public let tools: [Tool]?
        /// Tool choice configuration
        public let toolChoice: ToolChoice?
        /// Provider-specific metadata to pass to the LLM
        public let metadata: [String: Value]?

        /// Creates the parameters for a `sampling/createMessage` request, asking the client to run an LLM
        /// completion on the server's behalf.
        ///
        /// - Parameters:
        ///   - messages: The conversation so far, oldest first.
        ///   - modelPreferences: Advisory model-selection preferences. Defaults to `nil`.
        ///   - systemPrompt: System prompt the client may apply. Defaults to `nil`.
        ///   - includeContext: Which MCP server context to include; deprecated values `thisServer` and
        ///     `allServers` should be avoided. Defaults to `nil`.
        ///   - temperature: Sampling temperature, nominally 0.0...1.0. Defaults to `nil` (client decides).
        ///   - maxTokens: Upper bound on tokens to generate. Required.
        ///   - stopSequences: Strings that end generation when produced. Defaults to `nil`.
        ///   - _meta: Protocol-reserved request metadata (e.g. a progress token). Defaults to `nil`.
        ///   - tools: Tools the model may call during sampling. Defaults to `nil`.
        ///   - toolChoice: Constraint on tool use. Defaults to `nil`.
        ///   - metadata: Provider-specific passthrough values. Defaults to `nil`.
        public init(
            messages: [Sampling.Message],
            modelPreferences: Sampling.ModelPreferences? = nil,
            systemPrompt: String? = nil,
            includeContext: Sampling.ContextInclusion? = nil,
            temperature: Double? = nil,
            maxTokens: Int,
            stopSequences: [String]? = nil,
            _meta: Metadata? = nil,
            tools: [Tool]? = nil,
            toolChoice: ToolChoice? = nil,
            metadata: [String: Value]? = nil
        ) {
            self.messages = messages
            self.modelPreferences = modelPreferences
            self.systemPrompt = systemPrompt
            self.includeContext = includeContext
            self.temperature = temperature
            self.maxTokens = maxTokens
            self.stopSequences = stopSequences
            self._meta = _meta
            self.tools = tools
            self.toolChoice = toolChoice
            self.metadata = metadata
        }
    }

    /// The result returned in response to the `CreateSamplingMessage` request.
    public struct Result: Hashable, Codable, Sendable {
        /// Name of the model used
        public let model: String
        /// Why sampling stopped
        public let stopReason: Sampling.StopReason?
        /// The role of the completion
        public let role: Sampling.Message.Role
        /// The completion content
        public let content: Sampling.Message.Content
        /// Optional metadata about this result
        public var _meta: Metadata?

        /// Creates the client's response to a `sampling/createMessage` request.
        ///
        /// - Parameters:
        ///   - model: Name of the model that produced the completion.
        ///   - stopReason: Why generation ended (see ``Sampling/StopReason``). Defaults to `nil`.
        ///   - role: Role of the generated message; normally `.assistant`.
        ///   - content: The generated content, a single block or several.
        ///   - _meta: Protocol-reserved result metadata. Defaults to `nil`.
        public init(
            model: String,
            stopReason: Sampling.StopReason? = nil,
            role: Sampling.Message.Role,
            content: Sampling.Message.Content,
            _meta: Metadata? = nil
        ) {
            self.model = model
            self.stopReason = stopReason
            self.role = role
            self.content = content
            self._meta = _meta
        }

        private enum CodingKeys: String, CodingKey, CaseIterable {
            case model, stopReason, role, content, _meta
        }

        /// Encodes `model`, `role` and `content` always; `stopReason` and `_meta` are omitted when `nil`.
        ///
        /// - Parameter encoder: The encoder to write the value to.
        /// - Throws: An error if the underlying encoder fails.
        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(model, forKey: .model)
            try container.encodeIfPresent(stopReason, forKey: .stopReason)
            try container.encode(role, forKey: .role)
            try container.encode(content, forKey: .content)
            try container.encodeIfPresent(_meta, forKey: ._meta)
        }

        /// Decodes the `sampling/createMessage` result from a keyed container.
        ///
        /// Required: `model`, `role`, `content`. Optional: `stopReason`, `_meta`.
        ///
        /// - Parameter decoder: The decoder to read the value from.
        /// - Throws: `DecodingError` if a required key is missing or any key is malformed.
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            model = try container.decode(String.self, forKey: .model)
            stopReason = try container.decodeIfPresent(
                Sampling.StopReason.self, forKey: .stopReason)
            role = try container.decode(Sampling.Message.Role.self, forKey: .role)
            content = try container.decode(Sampling.Message.Content.self, forKey: .content)
            _meta = try container.decodeIfPresent(Metadata.self, forKey: ._meta)
        }
    }
}
