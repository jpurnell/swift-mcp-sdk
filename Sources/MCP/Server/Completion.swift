import Foundation

/// The Model Context Protocol (MCP) provides a standardized way for servers to offer
/// autocompletion suggestions for the arguments of prompts and resource templates.
///
/// - SeeAlso: https://modelcontextprotocol.io/specification/2025-11-25/server/utilities/completion/

// MARK: - Reference Types

/// A reference to a prompt by name.
///
/// This is a typealias for `Prompt.Reference` — the two types are equivalent.
public typealias PromptReference = Prompt.Reference

/// A reference to a resource by URI
public struct ResourceReference: Hashable, Codable, Sendable {
    /// The resource URI
    public let uri: String

    /// Creates a reference to a resource (or resource template) whose argument is being completed.
    ///
    /// - Parameter uri: The resource URI or URI template, as advertised by the server.
    public init(uri: String) {
        self.uri = uri
    }

    private enum CodingKeys: String, CodingKey {
        case type, uri
    }

    /// Encodes the reference as `{"type": "ref/resource", "uri": ...}`.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("ref/resource", forKey: .type)
        try container.encode(uri, forKey: .uri)
    }

    /// Decodes a `ref/resource` reference. Both `type` and `uri` are required.
    ///
    /// - Throws: `DecodingError` if either key is missing, or if `type` is anything other than
    ///   `"ref/resource"` (a `dataCorrupted` error on the `type` key).
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        guard type == "ref/resource" else {
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Expected ref/resource type"
            )
        }
        uri = try container.decode(String.self, forKey: .uri)
    }
}

/// A reference type for completion requests (either prompt or resource)
public enum CompletionReference: Hashable, Codable, Sendable {
    /// References a prompt by name
    case prompt(PromptReference)
    /// References a resource URI
    case resource(ResourceReference)

    private enum CodingKeys: String, CodingKey {
        case type
    }

    /// Decodes a completion reference by reading `type` and delegating to the matching reference type.
    ///
    /// `"ref/prompt"` decodes a ``PromptReference`` and `"ref/resource"` decodes a ``ResourceReference``.
    ///
    /// - Throws: `DecodingError` if `type` is missing, is any other value (`dataCorrupted`), or the chosen
    ///   reference fails to decode.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "ref/prompt":
            self = .prompt(try PromptReference(from: decoder))
        case "ref/resource":
            self = .resource(try ResourceReference(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown reference type: \(type)"
            )
        }
    }

    /// Encodes the wrapped reference directly, so the output is the flat `ref/prompt` or `ref/resource`
    /// object with no extra wrapper.
    public func encode(to encoder: Encoder) throws {
        switch self {
        case .prompt(let ref):
            try ref.encode(to: encoder)
        case .resource(let ref):
            try ref.encode(to: encoder)
        }
    }
}

// MARK: - Completion Request

/// To get completion suggestions, clients send a `completion/complete` request.
/// - SeeAlso: https://modelcontextprotocol.io/specification/2025-11-25/server/utilities/completion/
public enum Complete: Method {
    /// The JSON-RPC method name, `completion/complete`.
    public static let name = "completion/complete"

    /// Parameters for the `completion/complete` request.
    public struct Parameters: Hashable, Codable, Sendable {
        /// The reference to what is being completed
        public let ref: CompletionReference
        /// The argument being completed
        public let argument: Argument
        /// Optional context with already-resolved arguments
        public let context: Context?

        /// Creates the parameters for a `completion/complete` request.
        ///
        /// - Parameters:
        ///   - ref: The prompt or resource whose argument is being completed.
        ///   - argument: The argument name and the partial value typed so far.
        ///   - context: Optional values of other arguments already resolved; `nil` omits it.
        public init(
            ref: CompletionReference,
            argument: Argument,
            context: Context? = nil
        ) {
            self.ref = ref
            self.argument = argument
            self.context = context
        }

        /// The argument being completed
        public struct Argument: Hashable, Codable, Sendable {
            /// The argument name
            public let name: String
            /// The current value (partial or complete)
            public let value: String

            /// Creates the argument being completed.
            ///
            /// - Parameters:
            ///   - name: The argument's name, as declared by the prompt or resource template.
            ///   - value: The text entered so far, which may be partial or empty.
            public init(name: String, value: String) {
                self.name = name
                self.value = value
            }
        }

        /// Context containing already-resolved arguments
        public struct Context: Hashable, Codable, Sendable {
            /// A mapping of already-resolved argument names to their values
            public let arguments: [String: String]

            /// Creates context for a completion request.
            ///
            /// - Parameter arguments: Previously resolved argument values keyed by argument name.
            public init(arguments: [String: String]) {
                self.arguments = arguments
            }
        }
    }

    /// Result returned for the `completion/complete` request.
    public struct Result: Hashable, Codable, Sendable {
        /// The completion result
        public let completion: Completion
        /// Optional metadata about this result
        public var _meta: Metadata?
        /// Tells the client how to parse this result.
        public var resultType: ResultType?

        /// Creates a `completion/complete` result, typically from a server's completion handler.
        ///
        /// - Parameters:
        ///   - completion: The suggested values.
        ///   - _meta: Optional result metadata.
        ///   - resultType: How the client should parse the result; defaults to `.complete`.
        public init(
            completion: Completion,
            _meta: Metadata? = nil,
            resultType: ResultType? = .complete
        ) {
            self.completion = completion
            self._meta = _meta
            self.resultType = resultType
        }

        private enum CodingKeys: String, CodingKey, CaseIterable {
            case completion, _meta, resultType
        }

        /// Encodes the result. `completion` is always written; `_meta` and `resultType` are omitted when `nil`.
        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(completion, forKey: .completion)
            try container.encodeIfPresent(_meta, forKey: ._meta)
            try container.encodeIfPresent(resultType, forKey: .resultType)
        }

        /// Decodes a `completion/complete` result. Only `completion` is required; `_meta` is optional, and an
        /// unrecognised `resultType` string is tolerated and read as `nil` rather than throwing.
        ///
        /// - Throws: `DecodingError` if `completion` is missing or any present key has the wrong type.
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            completion = try container.decode(Completion.self, forKey: .completion)
            _meta = try container.decodeIfPresent(Metadata.self, forKey: ._meta)
            // An unrecognised tag from a future revision reads as absent rather than
            // throwing, so the rest of the result stays readable.
            resultType = try container.decodeIfPresent(String.self, forKey: .resultType)
                .flatMap(ResultType.init(rawValue:))
        }

        /// Completion result containing suggested values
        public struct Completion: Hashable, Codable, Sendable {
            /// Array of completion values (max 100 items)
            public let values: [String]
            /// Optional total number of available matches
            public let total: Int?
            /// Whether additional results exist
            public let hasMore: Bool?

            /// Creates a set of completion suggestions.
            ///
            /// - Parameters:
            ///   - values: The suggested values; the spec caps this at 100 items (not enforced here).
            ///   - total: Optional total number of matches available, which may exceed `values.count`.
            ///   - hasMore: Optional flag indicating more results exist beyond those returned.
            public init(
                values: [String],
                total: Int? = nil,
                hasMore: Bool? = nil
            ) {
                self.values = values
                self.total = total
                self.hasMore = hasMore
            }
        }
    }
}
