import Foundation
import Logging

private let httpTypesLogger = Logger(
    label: "mcp.transport.http.types",
    factory: { _ in SwiftLogNoOpLogHandler() }
)

// MARK: - Session ID Generator

/// Generates unique session identifiers for stateful HTTP server transports.
///
/// Conform to this protocol to provide custom session ID generation logic.
/// Session IDs **MUST** contain only visible ASCII characters (0x21–0x7E)
/// per the MCP specification.
///
/// A default implementation using secure random bytes is provided via ``UUIDSessionIDGenerator``.
public protocol SessionIDGenerator: Sendable {
    /// Generates a new unique session identifier.
    func generateSessionID() -> String
}

/// Default session ID generator that produces random hexadecimal strings.
///
/// Each ID is 32 bytes (256 bits) drawn from the system's cryptographically secure random
/// number generator, written as 64 lowercase hexadecimal digits, which are all within the valid
/// ASCII range (0x21–0x7E). A UUID is deliberately not used: RFC 9562 forbids treating one as
/// a security capability, and a session ID is exactly that.
public struct UUIDSessionIDGenerator: SessionIDGenerator {
    /// Number of random bytes in each generated ID.
    private static let byteCount = 32

    /// Creates a generator.
    public init() {}

    /// Generates a session ID from 32 random bytes, rendered as 64 lowercase hexadecimal characters.
    ///
    /// The bytes come from the system's cryptographically secure random number generator, so
    /// IDs are unguessable. Hex digits are within the visible ASCII range (0x21-0x7E).
    public func generateSessionID() -> String {
        var generator = SecureRandomNumberGenerator()
        var hex = ""
        hex.reserveCapacity(Self.byteCount * 2)
        for _ in 0..<Self.byteCount {
            let byte = UInt8.random(in: UInt8.min...UInt8.max, using: &generator)
            hex += byte < 0x10 ? "0" : ""
            hex += String(byte, radix: 16)
        }
        return hex
    }
}

// MARK: - HTTP Request

/// A framework-agnostic HTTP request representation.
///
/// This type decouples the transport from any specific HTTP framework.
/// The HTTP framework adapter converts its native request type into this before passing to the transport.
public struct HTTPRequest: Sendable {
    /// The HTTP method (e.g., "GET", "POST", "DELETE").
    public let method: String

    /// HTTP headers as key-value pairs.
    public let headers: [String: String]

    /// The request body data, if any.
    public let body: Data?

    /// The request path (e.g., "/mcp", "/.well-known/oauth-protected-resource").
    /// Used by validators that need to match on specific paths.
    public let path: String?

    /// Creates an HTTP request.
    ///
    /// - Parameters:
    ///   - method: The HTTP method.
    ///   - headers: The request headers. Defaults to none.
    ///   - body: The request body, if any.
    ///   - path: The request path, if known.
    public init(method: String, headers: [String: String] = [:], body: Data? = nil, path: String? = nil) {
        self.method = method
        self.headers = headers
        self.body = body
        self.path = path
    }

    /// Case-insensitive header lookup.
    public func header(_ name: String) -> String? {
        let lowercased = name.lowercased()
        return headers.first { $0.key.lowercased() == lowercased }?.value
    }
}

// MARK: - HTTP Response

/// A framework-agnostic HTTP response.
///
/// The HTTP framework adapter converts this into its native response type.
///
/// Use computed properties (`statusCode`, `headers`, `bodyData`) for generic access,
/// or switch on the enum for case-specific handling (e.g., streaming):
///
/// ```swift
/// import Foundation
/// import MCP
///
/// func describe(_ response: HTTPResponse) -> String {
///     switch response {
///     case .stream:
///         // Pipe the async stream to the HTTP response body
///         return "streaming body"
///     default:
///         // Use response.bodyData for the body
///         return "\(response.statusCode) with \(response.bodyData?.count ?? 0) bytes"
///     }
/// }
/// ```
public enum HTTPResponse: Sendable {
    /// 202 Accepted, no body. Used for notifications and client responses.
    case accepted(headers: [String: String] = [:])

    /// 200 OK, no body. Used for DELETE confirmation.
    case ok(headers: [String: String] = [:])

    /// 200 OK with data body (typically JSON).
    case data(Data, headers: [String: String] = [:])

    /// 200 OK with SSE streaming body.
    case stream(AsyncThrowingStream<Data, Swift.Error>, headers: [String: String] = [:])

    /// Error response with a JSON-RPC error body.
    /// The status code, headers, and body are derived automatically.
    case error(statusCode: Int, MCPError, sessionID: String? = nil, extraHeaders: [String: String] = [:])

    // MARK: - Computed Properties

    /// The HTTP status code.
    ///
    /// 202 for ``accepted(headers:)``; 200 for ``ok(headers:)``, ``data(_:headers:)`` and
    /// ``stream(_:headers:)``; the supplied code for ``error(statusCode:_:sessionID:extraHeaders:)``.
    public var statusCode: Int {
        switch self {
        case .accepted: 202
        case .ok, .data, .stream: 200
        case .error(let code, _, _, _): code
        }
    }

    /// The response headers. For an error response these include a JSON `Content-Type`, the session ID when one was given, and any extra headers, which take precedence.
    public var headers: [String: String] {
        switch self {
        case .accepted(let headers), .ok(let headers), .data(_, let headers), .stream(_, let headers):
            return headers
        case .error(_, _, let sessionID, let extraHeaders):
            var headers: [String: String] = [HTTPHeaderName.contentType: ContentType.json]
            if let sessionID { headers[HTTPHeaderName.sessionID] = sessionID }
            headers.merge(extraHeaders) { _, new in new }
            return headers
        }
    }

    /// The response body as data. `nil` for `.accepted`, `.ok`, and `.stream`.
    public var bodyData: Data? {
        switch self {
        case .accepted, .ok, .stream:
            return nil
        case .data(let data, _):
            return data
        case .error(_, let error, _, _):
            let errorBody: [String: Any] = [
                "jsonrpc": "2.0",
                "error": [
                    "code": error.code,
                    "message": error.errorDescription ?? "Unknown error",
                ],
                "id": NSNull(),
            ]
            do {
                return try JSONSerialization.data(withJSONObject: errorBody)
            } catch {
                httpTypesLogger.error(
                    "Failed to serialize error response body", metadata: ["error": "\(error)"])
                return nil
            }
        }
    }
}

// MARK: - HTTP Header Names

/// Standard header names used by the MCP Streamable HTTP transport.
public enum HTTPHeaderName {
    /// The `MCP-Session-Id` header, which carries the session identifier.
    public static let sessionID = "MCP-Session-Id"
    /// The `MCP-Protocol-Version` header, which carries the negotiated protocol version.
    public static let protocolVersion = "MCP-Protocol-Version"
    /// The `Last-Event-ID` header, used to resume an SSE stream after a disconnect.
    public static let lastEventID = "Last-Event-ID"
    /// The `Accept` header, listing the content types the client can receive.
    public static let accept = "Accept"
    /// The `Content-Type` header, naming the media type of the body.
    public static let contentType = "Content-Type"
    /// The `Authorization` header, which carries credentials such as a bearer token.
    public static let authorization = "Authorization"
    /// The `WWW-Authenticate` header, which carries an authentication challenge.
    public static let wwwAuthenticate = "WWW-Authenticate"
    /// The `Origin` header, which names the origin of a browser request.
    public static let origin = "Origin"
    /// The `Host` header, which names the host the request was addressed to.
    public static let host = "Host"
    /// The `Cache-Control` header, which directs caching behavior.
    public static let cacheControl = "Cache-Control"
    /// The `Connection` header, which controls whether the connection persists.
    public static let connection = "Connection"
    /// The `Allow` header, which lists the methods a resource supports.
    public static let allow = "Allow"
}

// MARK: - Content Types

enum ContentType {
    static let json = "application/json"
    static let sse = "text/event-stream"
}

// MARK: - SSE Event

/// A Server-Sent Event (SSE) data structure.
///
/// Formats according to the SSE specification:
/// https://html.spec.whatwg.org/multipage/server-sent-events.html
struct SSEEvent: Sendable {
    var id: String?
    var event: String?
    var data: String
    var retry: Int?

    /// Formats the event as SSE wire data.
    func formatted() -> Data {
        var result = ""
        if let id {
            result += "id: \(id)\n"
        }
        if let event {
            result += "event: \(event)\n"
        }
        if let retry {
            result += "retry: \(retry)\n"
        }
        result += "data: \(data)\n\n"
        return Data(result.utf8)
    }

    /// Creates a priming event with an empty data field.
    /// Per spec, this is sent immediately to prime the client for reconnection.
    static func priming(id: String, retry: Int? = nil) -> SSEEvent {
        SSEEvent(id: id, event: nil, data: "", retry: retry)
    }

    /// Creates a message event wrapping JSON-RPC data.
    static func message(data: Data, id: String? = nil) -> SSEEvent {
        SSEEvent(
            id: id,
            event: "message",
            data: String(decoding: data, as: UTF8.self)
        )
    }
}

// MARK: - HTTP Context Providing

/// A transport that can surface the originating HTTP request for an in-flight JSON-RPC
/// request, keyed by its JSON-RPC id.
///
/// The server consults this during dispatch so that registered method handlers can
/// observe the HTTP request that triggered them (headers, auth, path, body) via
/// ``Server/currentHandlerContext``, without changing the `withMethodHandler` signature.
///
/// Only JSON-RPC *requests* (with an id) are addressable — notifications have no id and
/// are not correlated.
public protocol HTTPContextProviding: Sendable {
    /// Returns the HTTP request associated with the given JSON-RPC id, if the
    /// transport still has it on hand. Implementations must return `nil` once the
    /// corresponding response has been delivered or the session has terminated.
    func httpRequestContext(for id: ID) async -> HTTPRequest?
}

// MARK: - JSON-RPC Message Classification

/// Classifies a raw JSON-RPC message for routing purposes.
///
/// Used by transports to determine where to route outgoing messages:
/// - Responses are routed to the originating request's stream
/// - Notifications and server requests are routed to the standalone GET stream
package enum JSONRPCMessageKind {
    case request(id: String, method: String)
    case notification(method: String)
    case response(id: String)

    /// Attempts to classify raw JSON-RPC data.
    /// Returns `nil` if the data cannot be parsed or classified.
    package init?(data: Data) {
        let parsed: Any
        do {
            parsed = try JSONSerialization.jsonObject(with: data)
        } catch {
            httpTypesLogger.debug(
                "Message is not valid JSON; cannot classify", metadata: ["error": "\(error)"])
            return nil
        }
        guard let json = parsed as? [String: Any] else {
            return nil
        }

        let id = Self.extractID(from: json)

        if let method = json["method"] as? String {
            if let id {
                self = .request(id: id, method: method)
            } else {
                self = .notification(method: method)
            }
        } else if json["result"] != nil || json["error"] != nil {
            guard let id else { return nil }
            self = .response(id: id)
        } else {
            return nil
        }
    }

    /// Whether this message is an `initialize` request.
    package var isInitializeRequest: Bool {
        if case .request(_, let method) = self {
            return method == "initialize"
        }
        return false
    }

    private static func extractID(from json: [String: Any]) -> String? {
        if let stringID = json["id"] as? String {
            return stringID
        } else if let intID = json["id"] as? Int {
            return String(intID)
        }
        return nil
    }
}
