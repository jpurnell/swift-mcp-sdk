import class Foundation.JSONDecoder
import class Foundation.JSONEncoder

private let jsonrpc = "2.0"

/// A type whose value may be omitted from the wire and rebuilt locally.
///
/// Decoding a message whose `params` is absent or `null` falls back to `init()` for types that
/// conform, instead of failing with a missing-key error.
public protocol NotRequired {
    init()
}

/// An empty parameter or result payload.
///
/// Used as the default `Parameters` and `Result` of a ``Method`` that carries no data.
public struct Empty: NotRequired, Hashable, Codable, Sendable {
    /// Creates an empty payload.
    public init() {}
}

extension Value: NotRequired {
    /// Creates the `null` value, used when `params` is omitted.
    public init() {
        self = .null
    }
}

// MARK: -

/// Describes one JSON-RPC method: its wire name and the types of its parameters and result.
///
/// Conform an empty enum to declare a method; Request and Response are generic over it.
public protocol Method: Sendable {
    /// The type of the `params` member. Defaults to Empty.
    associatedtype Parameters: Codable, Hashable, Sendable = Empty
    /// The type of the `result` member of a successful response. Defaults to Empty.
    associatedtype Result: Codable, Hashable, Sendable = Empty
    /// The JSON-RPC method string sent on the wire, for example `"tools/list"`.
    static var name: String { get }
}

/// Type-erased method for request/response handling
struct AnyMethod: Method, Sendable {
    static var name: String { "" }
    typealias Parameters = Value
    typealias Result = Value
}

extension Method where Parameters == Empty {
    /// Create a request for a method that takes no parameters.
    ///
    /// - Parameter id: The request ID. Defaults to a random ID.
    /// - Returns: A request carrying empty parameters.
    public static func request(
        id: ID = .random
    ) -> Request<Self> {
        Request(id: id, method: name, params: Empty())
    }
}

extension Method where Result == Empty {
    /// Create a response for a method whose result is empty.
    ///
    /// - Parameter id: The ID of the request being answered.
    /// - Returns: A successful response carrying an empty result.
    public static func response(id: ID) -> Response<Self> {
        Response(id: id, result: Empty())
    }
}

extension Method {
    /// Builds a request for this method carrying the given parameters.
    ///
    /// - Parameters:
    ///   - id: The request ID. Defaults to a random ID.
    ///   - parameters: The method's parameters.
    /// - Returns: A request whose `method` is this type's `name`.
    public static func request(
        id: ID = .random,
        _ parameters: Self.Parameters
    ) -> Request<Self> {
        Request(id: id, method: name, params: parameters)
    }

    /// Builds a successful response to a request for this method.
    ///
    /// - Parameters:
    ///   - id: The ID of the request being answered.
    ///   - result: The method's result.
    /// - Returns: A response holding `result` as its success value.
    public static func response(
        id: ID,
        result: Self.Result
    ) -> Response<Self> {
        Response(id: id, result: result)
    }

    /// Builds a failed response to a request for this method.
    ///
    /// - Parameters:
    ///   - id: The ID of the request being answered.
    ///   - error: The error to report to the requester.
    /// - Returns: A response holding `error` as its failure value.
    public static func response(
        id: ID,
        error: MCPError
    ) -> Response<Self> {
        Response(id: id, error: error)
    }
}

// MARK: -

/// A JSON-RPC 2.0 request for method `M`, pairing a caller-chosen ID with the method name and parameters.
public struct Request<M: Method>: Hashable, Identifiable, Codable, Sendable {
    /// The ID the receiver echoes in its response so the caller can correlate the two.
    public let id: ID
    /// The wire method name, for example `"tools/call"`.
    public let method: String
    /// The method's typed parameters; encoded as the `params` member.
    public let params: M.Parameters

    init(
        id: ID = .random,
        method: String,
        params: M.Parameters
    ) {
        self.id = id
        self.method = method
        self.params = params
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case jsonrpc, id, method, params
    }

    /// Encodes the request as a JSON-RPC 2.0 object with `jsonrpc`, `id`, `method` and `params`.
    ///
    /// - Parameter encoder: The encoder to write to.
    /// - Throws: Any error raised while encoding a member.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(jsonrpc, forKey: .jsonrpc)
        try container.encode(id, forKey: .id)
        try container.encode(method, forKey: .method)
        try container.encode(params, forKey: .params)
    }
}

extension Request {
    /// Decodes a JSON-RPC 2.0 request.
    ///
    /// Parameters of a ``NotRequired`` type may be absent or `null`.
    ///
    /// - Parameter decoder: The decoder to read from.
    /// - Throws: `DecodingError` if the version is not `2.0` or a required member is missing or malformed.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(String.self, forKey: .jsonrpc)
        guard version == jsonrpc else {
            throw DecodingError.dataCorruptedError(
                forKey: .jsonrpc, in: container, debugDescription: "Invalid JSON-RPC version")
        }
        id = try container.decode(ID.self, forKey: .id)
        method = try container.decode(String.self, forKey: .method)

        if M.Parameters.self is NotRequired.Type {
            // For NotRequired parameters, use decodeIfPresent or init()
            // The `is NotRequired.Type` test above is what makes both casts sound. Written
            // conditionally anyway, so that a future change to that test surfaces as a decoding
            // error naming the type rather than as a trap inside Foundation's decoder.
            if let decoded = try container.decodeIfPresent(M.Parameters.self, forKey: .params) {
                params = decoded
            } else {
                guard let notRequired = M.Parameters.self as? any NotRequired.Type,
                    let empty = notRequired.init() as? M.Parameters
                else {
                    throw DecodingError.dataCorrupted(
                        DecodingError.Context(
                            codingPath: container.codingPath,
                            debugDescription:
                                "\(M.Parameters.self) claims NotRequired but cannot be built empty"))
                }
                params = empty
            }
        } else if let value = try? container.decode(M.Parameters.self, forKey: .params) {
            // If params exists and can be decoded, use it
            params = value
        } else if try !container.contains(.params)
            || container.decodeNil(forKey: .params)
        {
            // If params is missing or explicitly null, use Empty for Empty parameters
            // or throw for non-Empty parameters
            if let empty = Empty() as? M.Parameters {
                params = empty
            } else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: container.codingPath,
                        debugDescription: "Missing required params field"))
            }
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "Invalid params field"))
        }
    }
}

/// A type-erased request for request/response handling
typealias AnyRequest = Request<AnyMethod>

extension AnyRequest {
    init<T: Method>(_ request: Request<T>) throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(request)
        self = try decoder.decode(AnyRequest.self, from: data)
    }
}

/// A box for request handlers that can be type-erased
// Justification: an abstract box with no stored state; concrete subclasses hold only an immutable handler closure
class RequestHandlerBox: @unchecked Sendable {
    func callAsFunction(_ request: AnyRequest) async throws -> AnyResponse {
        fatalError("Must override")
    }
}

/// A typed request handler that can be used to handle requests of a specific type
// Justification: holds one immutable @Sendable closure and no mutable state
final class TypedRequestHandler<M: Method>: RequestHandlerBox, @unchecked Sendable {
    private let _handle: @Sendable (Request<M>) async throws -> Response<M>

    init(_ handler: @escaping @Sendable (Request<M>) async throws -> Response<M>) {
        self._handle = handler
        super.init()
    }

    override func callAsFunction(_ request: AnyRequest) async throws -> AnyResponse {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        // Create a concrete request from the type-erased one
        let data = try encoder.encode(request)
        let request = try decoder.decode(Request<M>.self, from: data)

        // Handle with concrete type
        let response = try await _handle(request)

        // Convert result to AnyMethod response
        switch response.result {
        case .success(let result):
            let resultData = try encoder.encode(result)
            let resultValue = try decoder.decode(Value.self, from: resultData)
            return Response(id: response.id, result: resultValue)
        case .failure(let error):
            return Response(id: response.id, error: error)
        }
    }
}

// MARK: -

/// A JSON-RPC 2.0 response to a request for method `M`, carrying either a result or an error.
public struct Response<M: Method>: Hashable, Identifiable, Codable, Sendable {
    /// The ID of the request this response answers.
    public let id: ID
    /// The outcome: the method's result on success, or an `MCPError` on failure.
    public let result: Swift.Result<M.Result, MCPError>

    /// Creates a response from an explicit success or failure result.
    ///
    /// - Parameters:
    ///   - id: The ID of the request being answered.
    ///   - result: The outcome of the request.
    public init(
        id: ID,
        result: Swift.Result<M.Result, MCPError>
    ) {
        self.id = id
        self.result = result
    }

    /// Creates a successful response.
    ///
    /// - Parameters:
    ///   - id: The ID of the request being answered.
    ///   - result: The result of the request.
    public init(
        id: ID,
        result: M.Result
    ) {
        self.init(id: id, result: .success(result))
    }

    /// Creates a failed response.
    ///
    /// - Parameters:
    ///   - id: The ID of the request being answered.
    ///   - error: The error describing why the request failed.
    public init(
        id: ID,
        error: MCPError
    ) {
        self.init(id: id, result: .failure(error))
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case jsonrpc, id, result, error
    }

    /// Encodes the response as a JSON-RPC 2.0 object holding either `result` or `error`.
    ///
    /// - Parameter encoder: The encoder to write to.
    /// - Throws: Any error raised while encoding a member.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(jsonrpc, forKey: .jsonrpc)
        try container.encode(id, forKey: .id)

        switch result {
        case .success(let result):
            try container.encode(result, forKey: .result)
        case .failure(let error):
            try container.encode(error, forKey: .error)
        }
    }

    /// Decodes a JSON-RPC 2.0 response holding either a `result` or an `error`.
    ///
    /// - Parameter decoder: The decoder to read from.
    /// - Throws: `DecodingError` if the version is not `2.0` or neither a result nor an error can be read.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(String.self, forKey: .jsonrpc)
        guard version == jsonrpc else {
            throw DecodingError.dataCorruptedError(
                forKey: .jsonrpc, in: container, debugDescription: "Invalid JSON-RPC version")
        }
        id = try container.decode(ID.self, forKey: .id)
        if let result = try? container.decode(M.Result.self, forKey: .result) {
            self.result = .success(result)
        } else if let error = try? container.decode(MCPError.self, forKey: .error) {
            self.result = .failure(error)
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "Invalid response"))
        }
    }
}

/// A type-erased response for request/response handling
typealias AnyResponse = Response<AnyMethod>

extension AnyResponse {
    init<T: Method>(_ response: Response<T>) throws {
        switch response.result {
        case .success(let result):
            let data = try JSONEncoder().encode(result)
            let resultValue = try JSONDecoder().decode(Value.self, from: data)
            self = Response<AnyMethod>(
                id: response.id,
                result: .success(resultValue)
            )
        case .failure(let error):
            self = Response<AnyMethod>(
                id: response.id,
                result: .failure(error)
            )
        }
    }
}

// MARK: -

/// A notification message.
public protocol Notification: Hashable, Codable, Sendable {
    /// The parameters of the notification.
    associatedtype Parameters: Hashable, Codable, Sendable = Empty
    /// The name of the notification.
    static var name: String { get }
}

/// A type-erased notification for message handling
struct AnyNotification: Notification, Sendable {
    static var name: String { "" }
    typealias Parameters = Value
}

extension AnyNotification {
    init(_ notification: some Notification) throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(notification)
        self = try decoder.decode(AnyNotification.self, from: data)
    }
}

/// A JSON-RPC 2.0 notification for `N`: a method name and parameters with no ID and no response.
public struct Message<N: Notification>: Hashable, Codable, Sendable {
    /// The wire method name, for example `"notifications/initialized"`.
    public let method: String
    /// The notification's typed parameters; omitted from the wire when the type is Empty.
    public let params: N.Parameters

    /// Creates a notification message.
    ///
    /// - Parameters:
    ///   - method: The notification method name.
    ///   - params: The notification parameters.
    public init(method: String, params: N.Parameters) {
        self.method = method
        self.params = params
    }

    private enum CodingKeys: String, CodingKey {
        case jsonrpc, method, params
    }

    /// Encodes the notification as a JSON-RPC 2.0 object. `params` is omitted when the parameters are ``Empty``.
    ///
    /// - Parameter encoder: The encoder to write to.
    /// - Throws: Any error raised while encoding a member.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(jsonrpc, forKey: .jsonrpc)
        try container.encode(method, forKey: .method)
        if N.Parameters.self != Empty.self {
            try container.encode(params, forKey: .params)
        }
    }

    /// Decodes a JSON-RPC 2.0 notification.
    ///
    /// Parameters of a ``NotRequired`` type may be absent or `null`.
    ///
    /// - Parameter decoder: The decoder to read from.
    /// - Throws: `DecodingError` if the version is not `2.0` or required parameters are missing or malformed.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(String.self, forKey: .jsonrpc)
        guard version == jsonrpc else {
            throw DecodingError.dataCorruptedError(
                forKey: .jsonrpc, in: container, debugDescription: "Invalid JSON-RPC version")
        }
        method = try container.decode(String.self, forKey: .method)

        if N.Parameters.self is NotRequired.Type {
            // For NotRequired parameters, use decodeIfPresent or init()
            // The `is NotRequired.Type` test above is what makes both casts sound. Written
            // conditionally anyway, so that a future change to that test surfaces as a decoding
            // error naming the type rather than as a trap inside Foundation's decoder.
            if let decoded = try container.decodeIfPresent(N.Parameters.self, forKey: .params) {
                params = decoded
            } else {
                guard let notRequired = N.Parameters.self as? any NotRequired.Type,
                    let empty = notRequired.init() as? N.Parameters
                else {
                    throw DecodingError.dataCorrupted(
                        DecodingError.Context(
                            codingPath: container.codingPath,
                            debugDescription:
                                "\(N.Parameters.self) claims NotRequired but cannot be built empty"))
                }
                params = empty
            }
        } else if let value = try? container.decode(N.Parameters.self, forKey: .params) {
            // If params exists and can be decoded, use it
            params = value
        } else if try !container.contains(.params)
            || container.decodeNil(forKey: .params)
        {
            // If params is missing or explicitly null, use Empty for Empty parameters
            // or throw for non-Empty parameters
            if let empty = Empty() as? N.Parameters {
                params = empty
            } else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: container.codingPath,
                        debugDescription: "Missing required params field"))
            }
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "Invalid params field"))
        }
    }
}

/// A type-erased message for message handling
typealias AnyMessage = Message<AnyNotification>

extension Notification where Parameters == Empty {
    /// Builds a notification message for a notification that takes no parameters.
    ///
    /// - Returns: A message whose `method` is this type's `name` and whose parameters are `Empty`.
    public static func message() -> Message<Self> {
        Message(method: name, params: Empty())
    }
}

extension Notification {
    /// Builds a notification message with the given parameters.
    ///
    /// - Parameter parameters: The notification's parameters.
    /// - Returns: A message whose `method` is this type's `name`.
    public static func message(_ parameters: Parameters) -> Message<Self> {
        Message(method: name, params: parameters)
    }
}

/// A box for notification handlers that can be type-erased
// Justification: an abstract box with no stored state; concrete subclasses hold only an immutable notification closure
class NotificationHandlerBox: @unchecked Sendable {
    func callAsFunction(_ notification: Message<AnyNotification>) async throws {}
}

/// A typed notification handler that can be used to handle notifications of a specific type
// Justification: holds one immutable @Sendable notification closure and no mutable state
final class TypedNotificationHandler<N: Notification>: NotificationHandlerBox,
    @unchecked Sendable
{
    private let _handle: @Sendable (Message<N>) async throws -> Void

    init(_ handler: @escaping @Sendable (Message<N>) async throws -> Void) {
        self._handle = handler
        super.init()
    }

    override func callAsFunction(_ notification: Message<AnyNotification>) async throws {
        // Create a concrete notification from the type-erased one
        let data = try JSONEncoder().encode(notification)
        let typedNotification = try JSONDecoder().decode(Message<N>.self, from: data)

        try await _handle(typedNotification)
    }
}
