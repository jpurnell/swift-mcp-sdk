import Foundation

/// The Model Context Protocol (MCP) provides a standardized way
/// for servers to expose resources to clients.
/// Resources allow servers to share data that provides context to language models,
/// such as files, database schemas, or application-specific information.
/// Each resource is uniquely identified by a URI.
///
/// - SeeAlso: https://modelcontextprotocol.io/specification/2025-11-25/server/resources/
public struct Resource: Hashable, Codable, Sendable {
    /// The resource name
    public var name: String
    /// A human-readable resource title
    public var title: String?
    /// The resource URI
    public var uri: String
    /// The resource description
    public var description: String?
    /// The resource MIME type
    public var mimeType: String?
    /// Raw content size in bytes
    public var size: Int?
    /// Annotations for this resource
    public var annotations: Resource.Annotations?
    /// Optional set of sized icons that the client can display in a user interface
    public var icons: [Icon]?
    /// Metadata fields for the resource (see spec for _meta usage)
    public var _meta: Metadata?

    /// Creates a `Resource` with the given values.
    public init(
        name: String,
        uri: String,
        title: String? = nil,
        description: String? = nil,
        mimeType: String? = nil,
        size: Int? = nil,
        annotations: Resource.Annotations? = nil,
        icons: [Icon]? = nil,
        _meta: Metadata? = nil
    ) {
        self.name = name
        self.title = title
        self.uri = uri
        self.description = description
        self.mimeType = mimeType
        self.size = size
        self.annotations = annotations
        self.icons = icons
        self._meta = _meta
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case uri
        case title
        case description
        case mimeType
        case size
        case annotations
        case icons
        case _meta
    }

    /// Creates a `Resource` by decoding it from the given decoder, throwing `DecodingError` if the data is malformed.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        uri = try container.decode(String.self, forKey: .uri)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        mimeType = try container.decodeIfPresent(String.self, forKey: .mimeType)
        size = try container.decodeIfPresent(Int.self, forKey: .size)
        annotations = try container.decodeIfPresent(Resource.Annotations.self, forKey: .annotations)
        icons = try container.decodeIfPresent([Icon].self, forKey: .icons)
        _meta = try container.decodeIfPresent(Metadata.self, forKey: ._meta)
    }

    /// Encodes this `Resource` into the given encoder using its MCP wire format.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(uri, forKey: .uri)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(mimeType, forKey: .mimeType)
        try container.encodeIfPresent(size, forKey: .size)
        try container.encodeIfPresent(annotations, forKey: .annotations)
        try container.encodeIfPresent(icons, forKey: .icons)
        try container.encodeIfPresent(_meta, forKey: ._meta)
    }

    /// Content of a resource.
    public struct Content: Hashable, Codable, Sendable {
        /// The resource URI
        public let uri: String
        /// The resource MIME type
        public let mimeType: String?
        /// The resource text content
        public let text: String?
        /// The resource binary content
        public let blob: String?
        /// Metadata fields (see spec for _meta usage)
        public var _meta: Metadata?

        /// Creates text resource content (UTF-8 string) for a resource URI.
        public static func text(
            _ content: String,
            uri: String,
            mimeType: String? = nil,
            _meta: Metadata? = nil
        ) -> Self {
            .init(uri: uri, mimeType: mimeType, text: content, _meta: _meta)
        }

        /// Creates binary resource content (delivered base64-encoded) for a resource URI.
        public static func binary(
            _ data: Data,
            uri: String,
            mimeType: String? = nil,
            _meta: Metadata? = nil
        ) -> Self {
            .init(
                uri: uri,
                mimeType: mimeType,
                blob: data.base64EncodedString(),
                _meta: _meta
            )
        }

        private init(
            uri: String,
            mimeType: String? = nil,
            text: String? = nil,
            _meta: Metadata? = nil
        ) {
            self.uri = uri
            self.mimeType = mimeType
            self.text = text
            self.blob = nil
            self._meta = _meta
        }

        private init(
            uri: String,
            mimeType: String? = nil,
            blob: String,
            _meta: Metadata? = nil
        ) {
            self.uri = uri
            self.mimeType = mimeType
            self.text = nil
            self.blob = blob
            self._meta = _meta
        }

        private enum CodingKeys: String, CodingKey {
            case uri
            case mimeType
            case text
            case blob
            case _meta
        }

        /// Creates a `Resource.Content` by decoding it from the given decoder, throwing `DecodingError` if the data is malformed.
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            uri = try container.decode(String.self, forKey: .uri)
            mimeType = try container.decodeIfPresent(String.self, forKey: .mimeType)
            text = try container.decodeIfPresent(String.self, forKey: .text)
            blob = try container.decodeIfPresent(String.self, forKey: .blob)
            _meta = try container.decodeIfPresent(Metadata.self, forKey: ._meta)
        }

        /// Encodes this `Resource.Content` into the given encoder using its MCP wire format.
        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(uri, forKey: .uri)
            try container.encodeIfPresent(mimeType, forKey: .mimeType)
            try container.encodeIfPresent(text, forKey: .text)
            try container.encodeIfPresent(blob, forKey: .blob)
            try container.encodeIfPresent(_meta, forKey: ._meta)
        }
    }

    /// A resource template.
    public struct Template: Hashable, Codable, Sendable {
        /// The URI template pattern
        public var uriTemplate: String
        /// The template name
        public var name: String
        /// A human-readable template title
        public var title: String?
        /// The template description
        public var description: String?
        /// The resource MIME type
        public var mimeType: String?
        /// Annotations for this template
        public var annotations: Resource.Annotations?
        /// Optional set of sized icons that the client can display in a user interface
        public var icons: [Icon]?
        /// Metadata fields for the template (see spec for _meta usage)
        public var _meta: Metadata?

        /// Creates a `Resource.Template` with the given values.
        public init(
            uriTemplate: String,
            name: String,
            title: String? = nil,
            description: String? = nil,
            mimeType: String? = nil,
            annotations: Resource.Annotations? = nil,
            icons: [Icon]? = nil,
            _meta: Metadata? = nil
        ) {
            self.uriTemplate = uriTemplate
            self.name = name
            self.title = title
            self.description = description
            self.mimeType = mimeType
            self.annotations = annotations
            self.icons = icons
            self._meta = _meta
        }
    }

    // A resource annotation.
    /// Optional hints that tell clients how a resource should be used or displayed: its intended audience, priority, and last-modified time.
    public struct Annotations: Hashable, Codable, Sendable {
        /// The intended audience for this resource.
        public enum Audience: String, Hashable, Codable, Sendable {
            /// Content intended for end users.
            case user = "user"
            /// Content intended for AI assistants.
            case assistant = "assistant"
        }

        /// An array indicating the intended audience(s) for this resource. For example, `[.user, .assistant]` indicates content useful for both.
        public let audience: [Audience]?
        /// A number from 0.0 to 1.0 indicating the importance of this resource. A value of 1 means "most important" (effectively required), while 0 means "least important".
        public let priority: Double?
        /// An ISO 8601 formatted timestamp indicating when the resource was last modified (e.g., "2025-01-12T15:00:58Z").
        public let lastModified: String?

        /// Creates a `Resource.Annotations` with the given values.
        public init(
            audience: [Audience]? = nil,
            priority: Double? = nil,
            lastModified: String? = nil
        ) {
            self.audience = audience
            self.priority = priority
            self.lastModified = lastModified
        }
    }
}

// MARK: -

/// To discover available resources, clients send a `resources/list` request.
/// - SeeAlso: https://modelcontextprotocol.io/specification/2025-11-25/server/resources/#listing-resources
public enum ListResources: Method {
    /// The JSON-RPC method name, `resources/list`.
    public static let name: String = "resources/list"

    /// Parameters for the `resources/list` request.
    public struct Parameters: NotRequired, Hashable, Codable, Sendable {
        /// An opaque pagination cursor returned as `nextCursor` by a previous response; omit to start from the first page.
        public let cursor: String?

        /// Creates an empty `ListResources.Parameters`.
        public init() {
            self.cursor = nil
        }

        /// Creates parameters that request the page identified by `cursor`.
        public init(cursor: String) {
            self.cursor = cursor
        }
    }

    /// Result returned for the `resources/list` request.
    public struct Result: Hashable, Codable, Sendable {
        /// The resources on this page of results.
        public let resources: [Resource]
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

        /// Creates a `ListResources.Result` with the given values.
        public init(
            resources: [Resource],
            nextCursor: String? = nil,
            _meta: Metadata? = nil,
            resultType: ResultType? = .complete,
            ttlMs: Int? = nil,
            cacheScope: CacheScope? = nil
        ) {
            self.resources = resources
            self.nextCursor = nextCursor
            self._meta = _meta
            self.resultType = resultType
            self.ttlMs = ttlMs
            self.cacheScope = cacheScope
        }

        private enum CodingKeys: String, CodingKey, CaseIterable {
            case resources, nextCursor, _meta, resultType, ttlMs, cacheScope
        }

        /// Encodes this `ListResources.Result` into the given encoder using its MCP wire format.
        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(resources, forKey: .resources)
            try container.encodeIfPresent(nextCursor, forKey: .nextCursor)
            try container.encodeIfPresent(_meta, forKey: ._meta)
            try container.encodeIfPresent(resultType, forKey: .resultType)
            try container.encodeIfPresent(ttlMs, forKey: .ttlMs)
            try container.encodeIfPresent(cacheScope, forKey: .cacheScope)
        }

        /// Creates a `ListResources.Result` by decoding it from the given decoder, throwing `DecodingError` if the data is malformed.
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            resources = try container.decode([Resource].self, forKey: .resources)
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

/// To retrieve resource contents, clients send a `resources/read` request:
/// - SeeAlso: https://modelcontextprotocol.io/specification/2025-11-25/server/resources/#reading-resources
public enum ReadResource: Method {
    /// The JSON-RPC method name, `resources/read`.
    public static let name: String = "resources/read"

    /// Parameters for the `resources/read` request.
    public struct Parameters: Hashable, Codable, Sendable {
        /// The URI of the resource.
        public let uri: String

        /// Creates a `ReadResource.Parameters` with the given values.
        public init(uri: String) {
            self.uri = uri
        }
    }

    /// Result returned for the `resources/read` request.
    public struct Result: Hashable, Codable, Sendable {
        /// The contents of the requested resource (one or more text or binary parts).
        public let contents: [Resource.Content]
        /// Optional metadata about this result
        public var _meta: Metadata?
        /// Tells the client how to parse this result.
        public var resultType: ResultType?
        /// How long, in milliseconds, the client may consider this result fresh.
        public var ttlMs: Int?
        /// Whether a shared intermediary may cache this result.
        public var cacheScope: CacheScope?

        /// Creates a `ReadResource.Result` with the given values.
        public init(
            contents: [Resource.Content],
            _meta: Metadata? = nil,
            resultType: ResultType? = .complete,
            ttlMs: Int? = nil,
            cacheScope: CacheScope? = nil
        ) {
            self.contents = contents
            self._meta = _meta
            self.resultType = resultType
            self.ttlMs = ttlMs
            self.cacheScope = cacheScope
        }

        private enum CodingKeys: String, CodingKey, CaseIterable {
            case contents, _meta, resultType, ttlMs, cacheScope
        }

        /// Encodes this `ReadResource.Result` into the given encoder using its MCP wire format.
        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(contents, forKey: .contents)
            try container.encodeIfPresent(_meta, forKey: ._meta)
            try container.encodeIfPresent(resultType, forKey: .resultType)
            try container.encodeIfPresent(ttlMs, forKey: .ttlMs)
            try container.encodeIfPresent(cacheScope, forKey: .cacheScope)
        }

        /// Creates a `ReadResource.Result` by decoding it from the given decoder, throwing `DecodingError` if the data is malformed.
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            contents = try container.decode([Resource.Content].self, forKey: .contents)
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

/// To discover available resource templates, clients send a `resources/templates/list` request.
/// - SeeAlso: https://modelcontextprotocol.io/specification/2025-11-25/server/resources/#resource-templates
public enum ListResourceTemplates: Method {
    /// The JSON-RPC method name, `resources/templates/list`.
    public static let name: String = "resources/templates/list"

    /// Parameters for the `resources/templates/list` request.
    public struct Parameters: NotRequired, Hashable, Codable, Sendable {
        /// An opaque pagination cursor returned as `nextCursor` by a previous response; omit to start from the first page.
        public let cursor: String?

        /// Creates an empty `ListResourceTemplates.Parameters`.
        public init() {
            self.cursor = nil
        }

        /// Creates parameters that request the page identified by `cursor`.
        public init(cursor: String) {
            self.cursor = cursor
        }
    }

    /// Result returned for the `resources/templates/list` request.
    public struct Result: Hashable, Codable, Sendable {
        /// The resource templates on this page of results.
        public let templates: [Resource.Template]
        /// An opaque cursor to pass as `cursor` to fetch the next page; `nil` when there are no more results.
        public let nextCursor: String?
        /// Optional metadata about this result
        public var _meta: Metadata?
        /// Tells the client how to parse this result.
        public var resultType: ResultType?
        /// How long, in milliseconds, the client may consider this result fresh.
        public var ttlMs: Int?
        /// Whether a shared intermediary may cache this result.
        public var cacheScope: CacheScope?

        /// Creates a `ListResourceTemplates.Result` with the given values.
        public init(
            templates: [Resource.Template],
            nextCursor: String? = nil,
            _meta: Metadata? = nil,
            resultType: ResultType? = .complete,
            ttlMs: Int? = nil,
            cacheScope: CacheScope? = nil
        ) {
            self.templates = templates
            self.nextCursor = nextCursor
            self._meta = _meta
            self.resultType = resultType
            self.ttlMs = ttlMs
            self.cacheScope = cacheScope
        }

        private enum CodingKeys: String, CodingKey, CaseIterable {
            case templates = "resourceTemplates"
            case nextCursor
            case _meta, resultType, ttlMs, cacheScope
        }

        /// Encodes this `ListResourceTemplates.Result` into the given encoder using its MCP wire format.
        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(templates, forKey: .templates)
            try container.encodeIfPresent(nextCursor, forKey: .nextCursor)
            try container.encodeIfPresent(_meta, forKey: ._meta)
            try container.encodeIfPresent(resultType, forKey: .resultType)
            try container.encodeIfPresent(ttlMs, forKey: .ttlMs)
            try container.encodeIfPresent(cacheScope, forKey: .cacheScope)
        }

        /// Creates a `ListResourceTemplates.Result` by decoding it from the given decoder, throwing `DecodingError` if the data is malformed.
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            templates = try container.decode([Resource.Template].self, forKey: .templates)
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

/// When the list of available resources changes, servers that declared the listChanged capability SHOULD send a notification.
/// - SeeAlso: https://modelcontextprotocol.io/specification/2025-11-25/server/resources/#list-changed-notification
public struct ResourceListChangedNotification: Notification {
    /// The JSON-RPC notification name, `notifications/resources/list_changed`.
    public static let name: String = "notifications/resources/list_changed"

    /// The `notifications/resources/list_changed` notification carries no parameters.
    public typealias Parameters = Empty
}

/// Clients can subscribe to specific resources and receive notifications when they change.
/// - SeeAlso: https://modelcontextprotocol.io/specification/2025-11-25/server/resources/#subscriptions
public enum ResourceSubscribe: Method {
    /// The JSON-RPC method name, `resources/subscribe`.
    public static let name: String = "resources/subscribe"

    /// Parameters for the `resources/subscribe` request.
    public struct Parameters: Hashable, Codable, Sendable {
        /// The URI of the resource.
        public let uri: String
    }

    /// The `resources/subscribe` request returns an empty result on success.
    public typealias Result = Empty
}

/// Sent from the client to request cancellation of resources/updated notifications from the server. This should follow a previous resources/subscribe request.
/// - SeeAlso: https://modelcontextprotocol.io/specification/2025-06-18/schema#unsubscriberequest
public enum ResourceUnsubscribe: Method {
    /// The JSON-RPC method name, `resources/unsubscribe`.
    public static let name: String = "resources/unsubscribe"

    /// Parameters for the `resources/unsubscribe` request.
    public struct Parameters: Hashable, Codable, Sendable {
        /// The URI of the resource.
        public let uri: String
    }

    /// The `resources/unsubscribe` request returns an empty result on success.
    public typealias Result = Empty
}

/// When a resource changes, servers that declared the updated capability SHOULD send a notification to subscribed clients.
/// - SeeAlso: https://modelcontextprotocol.io/specification/2025-11-25/server/resources/#subscriptions
public struct ResourceUpdatedNotification: Notification {
    /// The JSON-RPC notification name, `notifications/resources/updated`.
    public static let name: String = "notifications/resources/updated"

    /// Parameters for the `notifications/resources/updated` notification.
    public struct Parameters: Hashable, Codable, Sendable {
        /// The URI of the resource.
        public let uri: String

        /// Creates a `ResourceUpdatedNotification.Parameters` with the given values.
        public init(uri: String) {
            self.uri = uri
        }
    }
}
