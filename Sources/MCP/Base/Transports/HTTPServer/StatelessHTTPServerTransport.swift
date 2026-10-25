import Foundation
import Logging

/// A stateless HTTP server transport that returns single JSON responses.
///
/// This transport implements a minimal subset of the MCP Streamable HTTP specification:
/// - No session management (no `Mcp-Session-Id` header)
/// - POST requests receive direct JSON responses (no SSE streaming)
/// - GET and DELETE requests return 405 Method Not Allowed
///
/// ## Usage
///
/// ```swift
/// import Foundation
/// import MCP
///
/// let server = Server(name: "MyServer", version: "1.0.0")
/// let transport = StatelessHTTPServerTransport()
///
/// // Start the MCP server with this transport
/// try await server.start(transport: transport)
///
/// // In your HTTP framework handler:
/// func handle(_ httpRequest: HTTPRequest) async -> HTTPResponse {
///     // Convert the response to your framework's response type and return it
///     await transport.handleRequest(httpRequest)
/// }
/// ```
///
/// ## When to Use
///
/// Use this transport when:
/// - You don't need server-initiated messages (no GET SSE stream)
/// - You want simple request-response semantics
/// - Session management is handled externally or not needed
///
/// For full streaming and session support, use ``StatefulHTTPServerTransport`` instead.
///
/// ## Concurrency
///
/// In-flight requests are correlated to their HTTP exchange by JSON-RPC id. Because ids are
/// client-scoped, a concurrent request that reuses an id already in flight is rejected with
/// HTTP 409 and a JSON-RPC `-32600` error rather than silently displacing the first request.
/// Clients must therefore keep ids unique among their own concurrent in-flight requests.
public actor StatelessHTTPServerTransport: Transport, HTTPContextProviding {
    /// The logger that receives this transport's diagnostics. A no-op logger is used if none was supplied.
    public nonisolated let logger: Logger

    // MARK: - Dependencies

    private let validationPipeline: any HTTPRequestValidationPipeline

    // MARK: - State

    private var terminated = false
    private var started = false

    // MARK: - Incoming message stream (client → server)

    private let incomingStream: AsyncThrowingStream<Data, Swift.Error>
    private let incomingContinuation: AsyncThrowingStream<Data, Swift.Error>.Continuation

    // MARK: - Response waiters

    /// Maps request ID → continuation waiting for the server's response.
    /// When the server calls `send()` with a response, the matching continuation is resumed.
    private var responseWaiters: [String: CheckedContinuation<Data, any Error>] = [:]

    /// Maps request ID → originating HTTP request, surfaced to handlers via
    /// ``Server/currentHTTPContext``. Entries live only while a JSON-RPC request
    /// is in flight.
    private var httpRequestContexts: [String: HTTPRequest] = [:]

    // MARK: - Init

    /// Creates a stateless HTTP server transport that answers each POST with one JSON response.
    ///
    /// The transport does nothing until ``connect()`` is called and an HTTP adapter forwards requests to
    /// ``handleRequest(_:)``.
    ///
    /// - Parameters:
    ///   - validationPipeline: The validators run on every POST. Defaults to `nil`, which uses localhost-only
    ///     origin validation, a JSON-only `Accept` check, a JSON `Content-Type` check and protocol-version
    ///     validation. Pass your own to add authentication or to allow other origins; it replaces the defaults
    ///     entirely.
    ///   - logger: Logger for transport diagnostics. Defaults to `nil`, which discards log output.
    public init(
        validationPipeline: (any HTTPRequestValidationPipeline)? = nil,
        logger: Logger? = nil
    ) {
        self.validationPipeline = validationPipeline ?? StandardValidationPipeline(validators: [
            OriginValidator.localhost(),
            AcceptHeaderValidator(mode: .jsonOnly),
            ContentTypeValidator(),
            ProtocolVersionValidator(),
        ])
        self.logger = logger ?? Logger(
            label: "mcp.transport.http.server.stateless",
            factory: { _ in SwiftLogNoOpLogHandler() }
        )

        let (stream, continuation) = AsyncThrowingStream<Data, Swift.Error>.makeStream()
        self.incomingStream = stream
        self.incomingContinuation = continuation
    }

    // MARK: - Transport Conformance

    /// Marks the transport as started so the server can use it.
    ///
    /// No resources are opened; HTTP requests arrive through ``handleRequest(_:)``.
    ///
    /// - Throws: `MCPError.internalError` if the transport has already been started.
    public func connect() async throws {
        guard !started else {
            throw MCPError.internalError("Transport already started")
        }
        started = true
        logger.debug("Stateless HTTP server transport started")
    }

    /// Terminates the transport: requests still waiting for a response are failed, the stream returned by
    /// ``receive()`` is finished, and later HTTP requests are answered with 404.
    public func disconnect() async {
        await terminate()
    }

    /// Routes outgoing server messages to the appropriate waiting HTTP handler.
    ///
    /// - Responses are matched by JSON-RPC ID and delivered to the waiting `handleRequest` call.
    /// - Notifications and server-initiated requests are logged and dropped
    ///   (no streaming channel available in stateless mode).
    ///
    /// A message that cannot be classified is logged and dropped, as is a response with no waiter (for example
    /// one that arrives after its request was cancelled).
    ///
    /// - Parameter data: One encoded outgoing JSON-RPC message.
    /// - Throws: `MCPError.connectionClosed` if the transport has been terminated.
    public func send(_ data: Data) async throws {
        guard !terminated else {
            throw MCPError.connectionClosed
        }

        guard let kind = JSONRPCMessageKind(data: data) else {
            logger.warning("Could not classify outgoing message for routing")
            return
        }

        switch kind {
        case .response(let id):
            guard let continuation = responseWaiters.removeValue(forKey: id) else {
                logger.debug(
                    "No waiter for response, may have timed out",
                    metadata: ["requestID": "\(id)"]
                )
                return
            }
            continuation.resume(returning: data)

        case .notification(let method):
            logger.debug(
                "Server-initiated notification dropped in stateless mode (no GET SSE stream)",
                metadata: ["method": "\(method)"]
            )

        case .request(_, let method):
            logger.debug(
                "Server-initiated request dropped in stateless mode (no GET SSE stream)",
                metadata: ["method": "\(method)"]
            )
        }
    }

    /// Returns the stream of client messages that ``handleRequest(_:)`` forwards to the server.
    ///
    /// Each element is the raw body of an accepted POST (request, notification or response). The stream
    /// finishes when the transport is terminated.
    ///
    /// - Returns: The single incoming-message stream; consume it from one reader.
    public func receive() -> AsyncThrowingStream<Data, Swift.Error> {
        incomingStream
    }

    // MARK: - HTTP Request Handler

    /// Handles an incoming HTTP request from the framework adapter.
    ///
    /// Only POST is supported:
    /// - **POST**: JSON-RPC messages (requests, notifications)
    /// - **GET**: 405 Method Not Allowed
    /// - **DELETE**: 405 Method Not Allowed
    /// - Others: 405 Method Not Allowed
    ///
    /// For a POST, the body must be a non-empty JSON-RPC message (400 otherwise) and pass the validation
    /// pipeline (whose error response is returned as is). Notifications and client responses are forwarded to the
    /// server and answered with 202. A request is forwarded and the call suspends until the server sends the
    /// matching response, which is returned as a JSON body; a request reusing an ID already in flight gets 409,
    /// and a failure while waiting gets 500.
    ///
    /// - Parameter request: The HTTP request received by the framework adapter.
    /// - Returns: The response for the adapter to write; 404 once the transport is terminated, and 405 with
    ///   `Allow: POST` for any method other than POST.
    public func handleRequest(_ request: HTTPRequest) async -> HTTPResponse {
        if terminated {
            return .error(
                statusCode: 404,
                .invalidRequest("Not Found: Transport has been terminated")
            )
        }

        switch request.method.uppercased() {
        case "POST":
            return await handlePost(request)
        default:
            return .error(
                statusCode: 405,
                .invalidRequest("Method Not Allowed"),
                extraHeaders: [HTTPHeaderName.allow: "POST"]
            )
        }
    }

    // MARK: - POST Handler

    private func handlePost(_ request: HTTPRequest) async -> HTTPResponse {
        // Parse body first to determine message type
        guard let body = request.body, !body.isEmpty else {
            return .error(
                statusCode: 400,
                .parseError("Empty request body")
            )
        }

        guard let messageKind = JSONRPCMessageKind(data: body) else {
            return .error(
                statusCode: 400,
                .parseError("Invalid JSON-RPC message")
            )
        }

        // Build validation context
        let context = HTTPValidationContext(
            httpMethod: "POST",
            sessionID: nil,
            isInitializationRequest: messageKind.isInitializeRequest,
            supportedProtocolVersions: Version.supported
        )

        // Run validation pipeline
        if let errorResponse = validationPipeline.validate(request, context: context) {
            return errorResponse
        }

        // Handle by message type
        switch messageKind {
        case .notification(let method):
            // Yield to server and return 202 Accepted
            incomingContinuation.yield(body)
            if method == CancelledNotification.name {
                completeExchangeForCancelledRequest(body)
            }
            return .accepted()

        case .response:
            // Yield to server and return 202 Accepted
            incomingContinuation.yield(body)
            return .accepted()

        case .request(let id, _):
            return await handleJSONRPCRequest(body, requestID: id, request: request)
        }
    }

    private func handleJSONRPCRequest(
        _ body: Data,
        requestID: String,
        request: HTTPRequest
    ) async -> HTTPResponse {
        // Reject a second request that reuses a JSON-RPC id already in flight.
        //
        // JSON-RPC ids are client-scoped, and this transport is explicitly multi-client, so
        // colliding ids across concurrent POSTs are legal and common (most clients start their
        // id sequence at 1). Keying per-request state on the raw id means a second request
        // would silently overwrite the first's response waiter (the first POST hangs forever
        // and its continuation leaks — issue #254) and its HTTP context (a handler could then
        // read another client's `Authorization` header — issue #265). Failing the duplicate
        // fast keeps every in-flight exchange isolated. Transparent support for concurrent
        // colliding ids arrives with the stateless core (SEP-2575).
        guard httpRequestContexts[requestID] == nil else {
            logger.warning(
                "Rejecting request: a JSON-RPC id is already in flight for another concurrent request",
                metadata: ["requestID": "\(requestID)"]
            )
            return .error(
                statusCode: 409,
                .invalidRequest(
                    "Duplicate in-flight JSON-RPC request id '\(requestID)'; "
                        + "ids must be unique among concurrent in-flight requests"
                )
            )
        }

        httpRequestContexts[requestID] = request
        // Yield the incoming message to the server
        incomingContinuation.yield(body)

        // Wait for the server to process and send a response
        let responseData: Data
        do {
            responseData = try await withCheckedThrowingContinuation { continuation in
                responseWaiters[requestID] = continuation
            }
        } catch {
            httpRequestContexts.removeValue(forKey: requestID)
            return .error(
                statusCode: 500,
                .internalError("Error processing request: \(error.localizedDescription)")
            )
        }

        httpRequestContexts.removeValue(forKey: requestID)
        return .data(responseData, headers: [HTTPHeaderName.contentType: ContentType.json])
    }

    // MARK: - Cancellation

    /// JSON-RPC error code for the synthesized "Request cancelled" response.
    ///
    /// MCP defines no cancellation error code; its schema designates [-32000, -32099] as
    /// "Implementation-specific JSON-RPC error codes". This SDK already uses -32000
    /// (connection closed) and -32001 (transport error), so -32002 is the next available.
    private static let requestCancelledErrorCode = -32002

    /// Completes the HTTP exchange for an in-flight request targeted by a
    /// `notifications/cancelled` notification.
    ///
    /// Per the MCP cancellation spec, the server sends no JSON-RPC response for a
    /// cancelled request (``Server`` suppresses it). But the Streamable HTTP transport
    /// requires that a POST carrying a JSON-RPC request receive a response: "the server
    /// MUST either return `Content-Type: text/event-stream` … or `Content-Type:
    /// application/json`, to return one JSON object". Without this method, nothing
    /// resumes the request's response waiter and the POST hangs until transport
    /// termination.
    ///
    /// To satisfy that MUST, the waiter is resumed with a synthesized JSON-RPC error
    /// response. Deviating from the cancellation SHOULD ("Not send a response for the
    /// cancelled request") is anticipated by the same spec: "The sender of the
    /// cancellation notification SHOULD ignore any response to the request that arrives
    /// afterward."
    ///
    /// Cancellations for unknown or already-completed requests are ignored, as the spec
    /// requires ("Invalid cancellation notifications SHOULD be ignored").
    ///
    /// - SeeAlso: https://modelcontextprotocol.io/specification/2025-11-25/basic/transports#sending-messages-to-the-server
    /// - SeeAlso: https://modelcontextprotocol.io/specification/2025-11-25/basic/utilities/cancellation
    private func completeExchangeForCancelledRequest(_ body: Data) {
        guard
            let notification = try? JSONDecoder().decode(
                Message<CancelledNotification>.self, from: body),
            let requestID = notification.params.requestId
        else {
            // Malformed or missing requestId — ignore per spec. Server logs it.
            return
        }

        guard let continuation = responseWaiters.removeValue(forKey: requestID.description)
        else {
            // Unknown or already-completed request — ignore per spec.
            return
        }

        var message = "Request cancelled"
        if let reason = notification.params.reason {
            message += ": \(reason)"
        }
        let response = AnyMethod.response(
            id: requestID,
            error: .serverError(code: Self.requestCancelledErrorCode, message: message)
        )

        do {
            // Match the wire format Server uses for outgoing messages.
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            continuation.resume(returning: try encoder.encode(response))
            logger.debug(
                "Completed HTTP exchange for cancelled request",
                metadata: ["requestID": "\(requestID)"]
            )
        } catch {
            logger.error(
                "Failed to encode cancellation response",
                metadata: ["requestID": "\(requestID)", "error": "\(error)"])
            continuation.resume(
                throwing: MCPError.internalError(
                    "Failed to encode cancellation response: \(error)"))
        }
    }

    // MARK: - HTTPContextProviding

    /// Returns the HTTP request for an in-flight JSON-RPC request.
    ///
    /// - Parameter id: The JSON-RPC ID of the request.
    /// - Returns: The originating HTTP request, or `nil` once its response has been delivered.
    public func httpRequestContext(for id: ID) -> HTTPRequest? {
        httpRequestContexts[id.description]
    }

    // MARK: - Termination

    private func terminate() async {
        guard !terminated else { return }
        terminated = true

        logger.debug("Stateless HTTP server transport terminated")

        // Cancel all waiting continuations
        for (id, continuation) in responseWaiters {
            continuation.resume(throwing: MCPError.connectionClosed)
            logger.debug("Cancelled waiter for request", metadata: ["requestID": "\(id)"])
        }
        responseWaiters.removeAll()
        httpRequestContexts.removeAll()

        // Close incoming stream
        incomingContinuation.finish()
    }
}
