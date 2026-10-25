import Foundation
import Logging

#if !os(Linux)
    import EventSource
#endif

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

// MARK: - Timeout Helpers

/// An implementation of the MCP Streamable HTTP transport protocol for clients.
///
/// This transport implements the [Streamable HTTP transport](https://spec.modelcontextprotocol.io/specification/2025-11-25/basic/transports#streamable-http)
/// specification from the Model Context Protocol (version 2025-11-25).
///
/// It supports:
/// - Sending JSON-RPC messages via HTTP POST requests
/// - Receiving responses via both direct JSON responses and SSE streams
/// - Session management using the `MCP-Session-Id` header
/// - Protocol version negotiation via `MCP-Protocol-Version` header
/// - Automatic reconnection for dropped SSE streams with resumability support
/// - Platform-specific optimizations for different operating systems
///
/// The transport supports two modes:
/// - Regular HTTP (`streaming=false`): Simple request/response pattern
/// - Streaming HTTP with SSE (`streaming=true`): Enables server-to-client push messages
///
/// - Important: Server-Sent Events (SSE) functionality is not supported on Linux platforms.
///
/// ## Example Usage
///
/// ```swift
/// import MCP
///
/// // Create a streaming HTTP transport with bearer token authentication
/// let transport = HTTPClientTransport(
///     endpoint: URL(string: "https://api.example.com/mcp")!,
///     requestModifier: { request in
///         var modifiedRequest = request
///         modifiedRequest.addValue("Bearer your-token-here", forHTTPHeaderField: "Authorization")
///         return modifiedRequest
///     }
/// )
///
/// // Initialize the client with streaming transport
/// let client = Client(name: "MyApp", version: "1.0.0")
/// try await client.connect(transport: transport)
///
/// // The transport will automatically handle SSE events
/// // and deliver them through the client's notification handlers
/// ```
public actor HTTPClientTransport: Transport {
    /// The single MCP endpoint URL that all POST requests (and the optional GET event stream) are sent to.
    public let endpoint: URL
    private let session: URLSession

    /// The session ID the server assigned via the `MCP-Session-Id` response header, or `nil` before one is
    /// issued or after the server reports the session expired (HTTP 404).
    ///
    /// Once set, it is sent as a header on every subsequent request.
    public private(set) var sessionID: String?

    /// The protocol version sent in the `MCP-Protocol-Version` request header; `nil` omits the header.
    ///
    /// Starts as the value passed at initialization; see `updateNegotiatedProtocolVersion(_:)`.
    public var protocolVersion: String?

    private let streaming: Bool
    private var streamingTask: Task<Void, Never>?

    /// The logger that receives this transport's diagnostics. A no-op logger is used if none was supplied.
    public nonisolated let logger: Logger

    /// The longest, in seconds, the transport waits for a session ID before opening the SSE stream anyway.
    public let sseInitializationTimeout: TimeInterval

    /// Closure to modify requests before they are sent
    private let requestModifier: (URLRequest) -> URLRequest

    /// Optional OAuth 2.1 authorizer.
    private let authorizer: (any HTTPClientAuthorizer)?

    private var isConnected = false
    private let messageStream: AsyncThrowingStream<Data, Swift.Error>
    private let messageContinuation: AsyncThrowingStream<Data, Swift.Error>.Continuation

    private var initialSessionIDSignalTask: Task<Void, Never>?
    private var initialSessionIDContinuation: CheckedContinuation<Void, Never>?

    /// The last event ID received from the server for SSE stream resumability
    private var lastEventID: String?

    /// The retry interval (in milliseconds) from the server's SSE `retry:` field
    private var retryInterval: Int = 3000  // Default 3000ms per SSE spec

    /// The underlying URLSession task for the active GET SSE stream.
    /// Used to trigger reconnection when a POST SSE stream closes without delivering data.
    private var activeGETSessionTask: URLSessionDataTask?

    /// Creates a Streamable HTTP client transport for one MCP endpoint, backed by its own `URLSession`.
    ///
    /// Nothing is sent until ``connect()`` is called.
    ///
    /// - Parameters:
    ///   - endpoint: The MCP endpoint URL.
    ///   - configuration: Configuration for the `URLSession` the transport creates. Defaults to `.default`.
    ///   - streaming: Whether to open a GET SSE stream for server-to-client messages after connecting.
    ///     Defaults to `true`; no stream is opened on Linux.
    ///   - sseInitializationTimeout: Seconds to wait for the server to assign a session ID before the SSE stream
    ///     is opened regardless. Defaults to 10.
    ///   - protocolVersion: Value for the `MCP-Protocol-Version` header. Defaults to `Version.latest`.
    ///   - authorizer: Optional ``HTTPClientAuthorizer`` that supplies the `Authorization` header and handles
    ///     401/403 challenges by acquiring a token and retrying. Defaults to `nil` (no authorization).
    ///   - requestModifier: Closure applied to every outgoing request after the SDK's headers are set, for
    ///     custom headers or signing. Defaults to the identity.
    ///   - logger: Logger for transport diagnostics. Defaults to `nil`, which discards log output.
    public init(
        endpoint: URL,
        configuration: URLSessionConfiguration = .default,
        streaming: Bool = true,
        sseInitializationTimeout: TimeInterval = 10,
        protocolVersion: String = Version.latest,
        authorizer: (any HTTPClientAuthorizer)? = nil,
        requestModifier: @escaping (URLRequest) -> URLRequest = { $0 },
        logger: Logger? = nil
    ) {
        self.init(
            endpoint: endpoint,
            session: URLSession(configuration: configuration),
            streaming: streaming,
            sseInitializationTimeout: sseInitializationTimeout,
            protocolVersion: protocolVersion,
            authorizer: authorizer,
            requestModifier: requestModifier,
            logger: logger
        )
    }

    internal init(
        endpoint: URL,
        session: URLSession,
        streaming: Bool = false,
        sseInitializationTimeout: TimeInterval = 10,
        protocolVersion: String = Version.latest,
        authorizer: (any HTTPClientAuthorizer)? = nil,
        requestModifier: @escaping (URLRequest) -> URLRequest = { $0 },
        logger: Logger? = nil
    ) {
        self.endpoint = endpoint
        self.session = session
        self.streaming = streaming
        self.sseInitializationTimeout = sseInitializationTimeout
        self.protocolVersion = protocolVersion
        self.requestModifier = requestModifier
        self.authorizer = authorizer

        // Create message stream
        var continuation: AsyncThrowingStream<Data, Swift.Error>.Continuation!
        self.messageStream = AsyncThrowingStream { continuation = $0 }
        self.messageContinuation = continuation

        self.logger =
            logger
            ?? Logger(
                label: "mcp.transport.http.client",
                factory: { _ in SwiftLogNoOpLogHandler() }
            )
    }

    // Setup the initial session ID signal
    private func setupInitialSessionIDSignal() {
        self.initialSessionIDSignalTask = Task {
            await withCheckedContinuation { continuation in
                self.initialSessionIDContinuation = continuation
            }
        }
    }

    // Trigger the initial session ID signal when a session ID is established
    private func triggerInitialSessionIDSignal() {
        if let continuation = self.initialSessionIDContinuation {
            continuation.resume()
            self.initialSessionIDContinuation = nil
            logger.debug("✓ Initial session ID signal triggered for SSE task")
        } else {
            logger.debug("✗ No continuation to trigger - signal already consumed or SSE task not waiting")
        }
    }

    /// Marks the transport connected and, when streaming is enabled, starts the background task that opens the
    /// GET SSE stream for server-initiated messages.
    ///
    /// No network request is made here for the POST path. Calling it while already connected does nothing.
    public func connect() async throws {
        guard !isConnected else { return }
        isConnected = true

        setupInitialSessionIDSignal()

        if streaming {
            streamingTask = Task { await startListeningForServerEvents() }
        }

        logger.debug("HTTP transport connected")
    }

    /// Stops the SSE task, invalidates and cancels the `URLSession`, and finishes the stream returned by
    /// ``receive()``.
    ///
    /// Calling it while not connected does nothing. The transport is not reusable afterwards, because the
    /// session and message stream are single-use.
    public func disconnect() async {
        guard isConnected else { return }
        isConnected = false

        streamingTask?.cancel()
        streamingTask = nil

        session.invalidateAndCancel()
        messageContinuation.finish()

        initialSessionIDSignalTask?.cancel()
        initialSessionIDSignalTask = nil
        initialSessionIDContinuation?.resume()
        initialSessionIDContinuation = nil

        logger.debug("HTTP clienttransport disconnected")
    }

    /// Updates the protocol version used for `MCP-Protocol-Version` headers on subsequent requests.
    ///
    /// Call this once version negotiation has completed so later requests carry the agreed version.
    ///
    /// - Parameter version: The negotiated protocol version string, for example `"2025-11-25"`.
    public func updateNegotiatedProtocolVersion(_ version: String) {
        self.protocolVersion = version
    }

    /// Sends one JSON-RPC message to the endpoint as an HTTP POST and routes the reply to ``receive()``.
    ///
    /// The request carries `Accept` for JSON and SSE, `Content-Type: application/json`, the protocol version
    /// and session ID headers when known, and the authorizer's `Authorization` header when configured; the
    /// `requestModifier` runs last. A JSON reply, or each event of an SSE reply, is yielded to the receive
    /// stream. A session ID in the response is captured. On a 401 or 403 with an authorizer, the challenge is
    /// handled and the POST retried up to the authorizer's `maxAuthorizationAttempts`.
    ///
    /// - Parameter data: The encoded JSON-RPC message, used as the request body.
    /// - Throws: `MCPError.internalError` if the transport is not connected, authorization setup or the
    ///   challenge flow fails, the response is not HTTP, or the status is an error (400, 401/403 without an
    ///   authorizer, 404 including an expired session, 405, 408, 429, 5xx). Errors from `URLSession` propagate.
    public func send(_ data: Data) async throws {
        guard isConnected else {
            throw MCPError.internalError("Transport not connected")
        }

        if let authorizer {
            do {
                try authorizer.validateEndpointSecurity(for: endpoint)
            } catch {
                throw MCPError.internalError(
                    "Authorization flow failed: \(error.localizedDescription)"
                )
            }
        }

        if let authorizer {
            do {
                try await authorizer.prepareAuthorization(for: endpoint, session: session)
            } catch {
                logger.warning(
                    "Authorization preparation failed; sending request without it",
                    metadata: ["error": "\(error)"])
            }
        }

        var attempts = 0
        let operationKey = jsonRPCOperationKey(from: data)

        // Bounded by the authorizer's attempt limit, which the retry path below also checks
        // before continuing. Stated here as well because a `while true` whose only bound is a
        // `continue` fifty lines down reads as unbounded, and one edit to that branch would
        // make it so. With no authorizer there is nothing to retry and the body returns on its
        // first pass.
        let maximumAttempts = authorizer?.maxAuthorizationAttempts ?? 1
        while attempts < maximumAttempts {
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.addValue(
                "\(ContentType.json), \(ContentType.sse)",
                forHTTPHeaderField: HTTPHeaderName.accept
            )
            request.addValue(ContentType.json, forHTTPHeaderField: HTTPHeaderName.contentType)
            request.httpBody = data

            if let protocolVersion = protocolVersion {
                request.addValue(protocolVersion, forHTTPHeaderField: HTTPHeaderName.protocolVersion)
            }

            if let sessionID = sessionID {
                request.addValue(sessionID, forHTTPHeaderField: HTTPHeaderName.sessionID)
            }

            if let authValue = authorizer?.authorizationHeader(for: endpoint) {
                request.setValue(authValue, forHTTPHeaderField: HTTPHeaderName.authorization)
            }

            request = requestModifier(request)

            do {
                #if os(Linux)
                    let (responseData, response) = try await session.data(for: request)
                    try await processResponse(response: response, data: responseData)
                #else
                    let (responseStream, response) = try await session.bytes(for: request)
                    try await processResponse(response: response, stream: responseStream)
                #endif
                return
            } catch let authError as HTTPAuthenticationChallengeError {
                guard let authorizer else {
                    throw mapAuthenticationChallengeError(authError)
                }

                let handled: Bool
                do {
                    handled = try await authorizer.handleChallenge(
                        statusCode: authError.statusCode,
                        headers: authError.headers,
                        endpoint: endpoint,
                        operationKey: operationKey,
                        session: session
                    )
                } catch {
                    throw MCPError.internalError(
                        "Authorization flow failed: \(error.localizedDescription)")
                }

                attempts += 1

                if handled, attempts < authorizer.maxAuthorizationAttempts {
                    continue
                }

                throw mapAuthenticationChallengeError(authError)
            }
        }

        // Reachable only if the attempt budget is exhausted without the retry path throwing,
        // which the branch above does not currently allow. Left explicit rather than trusting
        // that to stay true.
        throw MCPError.internalError("Authorization retries exhausted after \(attempts) attempts")
    }

    #if os(Linux)
        private func processResponse(response: URLResponse, data: Data) async throws {
            guard let httpResponse = response as? HTTPURLResponse else {
                throw MCPError.internalError("Invalid HTTP response")
            }

            let contentType = httpResponse.value(forHTTPHeaderField: HTTPHeaderName.contentType) ?? ""

            if let newSessionID = httpResponse.value(forHTTPHeaderField: HTTPHeaderName.sessionID) {
                let wasSessionIDNil = (self.sessionID == nil)
                self.sessionID = newSessionID
                if wasSessionIDNil {
                    triggerInitialSessionIDSignal()
                }
                logger.debug("Session ID received", metadata: ["sessionID": "\(newSessionID)"])
            }

            try processHTTPResponse(httpResponse, contentType: contentType)
            guard case 200..<300 = httpResponse.statusCode else { return }

            if contentType.contains(ContentType.sse) {
                logger.warning("SSE responses aren't fully supported on Linux")
                messageContinuation.yield(data)
            } else if contentType.contains(ContentType.json) {
                logger.trace("Received JSON response", metadata: ["size": "\(data.count)"])
                messageContinuation.yield(data)
            } else {
                logger.warning("Unexpected content type", metadata: ["contentType": "\(contentType)"])
            }
        }
    #else
        private func processResponse(response: URLResponse, stream: URLSession.AsyncBytes)
            async throws
        {
            guard let httpResponse = response as? HTTPURLResponse else {
                throw MCPError.internalError("Invalid HTTP response")
            }

            let contentType = httpResponse.value(forHTTPHeaderField: HTTPHeaderName.contentType) ?? ""

            if let newSessionID = httpResponse.value(forHTTPHeaderField: HTTPHeaderName.sessionID) {
                let wasSessionIDNil = (self.sessionID == nil)
                self.sessionID = newSessionID
                if wasSessionIDNil {
                    triggerInitialSessionIDSignal()
                }
                logger.debug("Session ID received", metadata: ["sessionID": "\(newSessionID)"])
            }

            try processHTTPResponse(httpResponse, contentType: contentType)
            guard case 200..<300 = httpResponse.statusCode else { return }

            if contentType.contains(ContentType.sse) {
                logger.trace("Received SSE response, processing in streaming task")
                let hadData = try await self.processSSE(stream)

                if !hadData {
                    logger.debug("POST SSE stream closed without data, triggering GET reconnection")
                    self.activeGETSessionTask?.cancel()
                }
            } else if contentType.contains(ContentType.json) {
                var buffer = Data()
                for try await byte in stream {
                    buffer.append(byte)
                }
                logger.trace("Received JSON response", metadata: ["size": "\(buffer.count)"])
                messageContinuation.yield(buffer)
            } else {
                logger.warning("Unexpected content type", metadata: ["contentType": "\(contentType)"])
            }
        }
    #endif

    private func processHTTPResponse(_ response: HTTPURLResponse, contentType: String) throws {
        switch response.statusCode {
        case 200..<300:
            return

        case 400:
            throw MCPError.internalError("Bad request")

        case 401:
            throw HTTPAuthenticationChallengeError(
                statusCode: response.statusCode,
                headers: responseHeaders(from: response)
            )

        case 403:
            throw HTTPAuthenticationChallengeError(
                statusCode: response.statusCode,
                headers: responseHeaders(from: response)
            )

        case 404:
            if sessionID != nil {
                logger.warning("Session has expired")
                sessionID = nil
                throw MCPError.internalError("Session expired")
            }
            throw MCPError.internalError("Endpoint not found")

        case 405:
            if streaming {
                self.streamingTask?.cancel()
                throw MCPError.internalError("Server does not support streaming")
            }
            throw MCPError.internalError("Method not allowed")

        case 408:
            throw MCPError.internalError("Request timeout")

        case 429:
            throw MCPError.internalError("Too many requests")

        case 500..<600:
            throw MCPError.internalError("Server error: \(response.statusCode)")

        default:
            throw MCPError.internalError(
                "Unexpected HTTP response: \(response.statusCode) (\(contentType))")
        }
    }

    private func mapAuthenticationChallengeError(_ error: HTTPAuthenticationChallengeError) -> MCPError {
        switch error.statusCode {
        case 401:
            return MCPError.internalError("Authentication required")
        case 403:
            return MCPError.internalError("Access forbidden")
        default:
            return MCPError.internalError("HTTP authorization error: \(error.statusCode)")
        }
    }

    private func responseHeaders(from response: HTTPURLResponse) -> [String: String] {
        var headers: [String: String] = [:]
        for (key, value) in response.allHeaderFields {
            guard let key = key as? String, let value = value as? String else { continue }
            headers[key] = value
        }
        return headers
    }

    private func jsonRPCOperationKey(from data: Data) -> String? {
        let parsed: Any
        do {
            parsed = try JSONSerialization.jsonObject(with: data)
        } catch {
            logger.debug("Outgoing payload is not JSON; no operation key", metadata: ["error": "\(error)"])
            return nil
        }
        guard let jsonObject = parsed as? [String: Any],
            let method = jsonObject["method"] as? String
        else {
            return nil
        }

        let normalized = method.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    /// Returns the stream of inbound messages: JSON replies to POSTs and events from SSE streams.
    ///
    /// Every call returns the same underlying stream, so it should be consumed by one reader. The stream
    /// finishes when ``disconnect()`` is called.
    ///
    /// - Returns: A stream yielding one `Data` per received message.
    public func receive() -> AsyncThrowingStream<Data, Swift.Error> {
        return messageStream
    }

    // MARK: - SSE

    private func startListeningForServerEvents() async {
        #if os(Linux)
            if streaming {
                logger.warning(
                    "SSE streaming was requested but is not fully supported on Linux. SSE connection will not be attempted."
                )
            }
        #else
            guard isConnected else { return }

            if self.sessionID == nil, let signalTask = self.initialSessionIDSignalTask {
                logger.debug(
                    "⏳ Waiting for session ID to be set",
                    metadata: ["timeoutSeconds": "\(self.sseInitializationTimeout)"])

                let startTime = Date()
                let timeout = self.sseInitializationTimeout
                do {
                    try await withThrowingTaskGroup { group in
                        group.addTask {
                            try await Task.sleep(for: .seconds(timeout))
                        }

                        group.addTask {
                            await signalTask.value
                        }

                        if let firstResult = try await group.next() {
                            group.cancelAll()
                            return firstResult
                        }
                    }
                } catch {
                    logger.warning(
                        "⏱️ Timeout waiting for session ID. SSE stream will proceed anyway.",
                        metadata: ["timeoutSeconds": "\(timeout)", "error": "\(error)"])
                }

                if self.sessionID != nil {
                    let elapsed = Date().timeIntervalSince(startTime)
                    logger.debug(
                        "✓ Session ID received, proceeding with SSE connection",
                        metadata: ["elapsedMs": "\(Int(elapsed * 1000))"])
                }
            } else {
                logger.debug("✓ Session ID already available, proceeding with SSE connection immediately")
            }

            var isFirstAttempt = true
            var attemptCount = 0

            logger.debug("🔄 Starting SSE retry loop", metadata: [
                "isConnected": "\(isConnected)",
                "isCancelled": "\(Task.isCancelled)"
            ])

            while isConnected && !Task.isCancelled {
                attemptCount += 1
                logger.debug("🔄 SSE retry loop iteration", metadata: [
                    "attempt": "\(attemptCount)",
                    "isFirstAttempt": "\(isFirstAttempt)"
                ])

                do {
                    if !isFirstAttempt {
                        let delayMs = self.retryInterval
                        logger.debug("⏳ Waiting before SSE reconnection", metadata: ["retryMs": "\(delayMs)"])
                        try await Task.sleep(for: .milliseconds(delayMs))
                        logger.debug("✓ Wait complete, reconnecting now")
                    }
                    isFirstAttempt = false

                    logger.debug("📡 Calling connectToEventStream", metadata: ["attempt": "\(attemptCount)"])

                    try await self.connectToEventStream()

                    logger.info("🔌 SSE stream closed gracefully, will reconnect", metadata: [
                        "attempt": "\(attemptCount)",
                        "willRetryAfter": "\(self.retryInterval)ms"
                    ])
                } catch {
                    if !Task.isCancelled {
                        logger.error(
                            "❌ SSE connection error",
                            metadata: ["attempt": "\(attemptCount)", "error": "\(error)"])
                    } else {
                        logger.debug("⏹️ SSE task cancelled")
                    }
                }

                logger.debug("🔄 End of retry loop iteration", metadata: [
                    "isConnected": "\(isConnected)",
                    "isCancelled": "\(Task.isCancelled)",
                    "willContinue": "\(isConnected && !Task.isCancelled)"
                ])
            }

            logger.debug("⏹️ SSE retry loop exited", metadata: [
                "isConnected": "\(isConnected)",
                "isCancelled": "\(Task.isCancelled)",
                "totalAttempts": "\(attemptCount)"
            ])
        #endif
    }

    #if !os(Linux)
        private func connectToEventStream() async throws {
            guard isConnected else {
                logger.debug("⚠️ Skipping connectToEventStream - transport not connected")
                return
            }

            if let authorizer {
                do {
                    try authorizer.validateEndpointSecurity(for: endpoint)
                } catch {
                    throw MCPError.internalError(
                        "Authorization flow failed: \(error.localizedDescription)"
                    )
                }
            }

            if let authorizer {
                do {
                    try await authorizer.prepareAuthorization(for: endpoint, session: session)
                } catch {
                    logger.warning(
                        "Authorization preparation failed; opening SSE stream without it",
                        metadata: ["error": "\(error)"])
                }
            }

            logger.debug("🔌 Preparing SSE connection request")

            var request = URLRequest(url: endpoint)
            request.httpMethod = "GET"
            request.addValue(ContentType.sse, forHTTPHeaderField: HTTPHeaderName.accept)
            request.addValue("no-cache", forHTTPHeaderField: HTTPHeaderName.cacheControl)

            if let protocolVersion = protocolVersion {
                request.addValue(protocolVersion, forHTTPHeaderField: HTTPHeaderName.protocolVersion)
            }

            if let sessionID = sessionID {
                request.addValue(sessionID, forHTTPHeaderField: HTTPHeaderName.sessionID)
            }

            if let lastEventID = lastEventID {
                request.addValue(lastEventID, forHTTPHeaderField: HTTPHeaderName.lastEventID)
                logger.info("→ Resuming SSE stream with Last-Event-ID", metadata: ["lastEventID": "\(lastEventID)"])
            } else {
                logger.info("→ Connecting to SSE stream (no last event ID to resume from)")
            }

            if let authValue = authorizer?.authorizationHeader(for: endpoint) {
                request.setValue(authValue, forHTTPHeaderField: HTTPHeaderName.authorization)
            }

            request = requestModifier(request)

            logger.debug("Starting SSE connection")

            let (stream, response) = try await session.bytes(for: request)
            self.activeGETSessionTask = stream.task

            guard let httpResponse = response as? HTTPURLResponse else {
                throw MCPError.internalError("Invalid HTTP response")
            }

            guard httpResponse.statusCode == 200 else {
                if httpResponse.statusCode == 405 {
                    self.streamingTask?.cancel()
                }
                throw MCPError.internalError("HTTP error: \(httpResponse.statusCode)")
            }

            if let newSessionID = httpResponse.value(forHTTPHeaderField: HTTPHeaderName.sessionID) {
                let wasSessionIDNil = (self.sessionID == nil)
                self.sessionID = newSessionID
                if wasSessionIDNil {
                    triggerInitialSessionIDSignal()
                }
                logger.debug("Session ID received", metadata: ["sessionID": "\(newSessionID)"])
            }

            defer { self.activeGETSessionTask = nil }
            try await self.processSSE(stream)
        }

        @discardableResult
        private func processSSE(_ stream: URLSession.AsyncBytes) async throws -> Bool {
            logger.debug("📥 Starting SSE event processing")
            var eventCount = 0
            var hadDataEvent = false

            for try await event in stream.events {
                eventCount += 1

                if Task.isCancelled {
                    logger.debug("⏹️ SSE processing cancelled", metadata: ["eventsProcessed": "\(eventCount)"])
                    break
                }

                logger.trace(
                    "SSE event received",
                    metadata: [
                        "type": "\(event.event ?? "message")",
                        "id": "\(event.id ?? "none")",
                    ]
                )

                if let eventID = event.id, !eventID.isEmpty {
                    self.lastEventID = eventID
                    logger.debug("Stored event ID for resumability", metadata: ["eventID": "\(eventID)"])
                }

                if let retry = event.retry {
                    self.retryInterval = retry
                    logger.debug("SSE retry interval updated", metadata: ["retryMs": "\(retry)"])
                }

                if !event.data.isEmpty, let data = event.data.data(using: .utf8) {
                    hadDataEvent = true
                    messageContinuation.yield(data)
                }
            }

            // Why the loop ended matters to the caller, which reads the return value to decide
            // whether to reconnect. A cancelled stream would otherwise report `false` — the same
            // answer as a stream that ran to completion having produced nothing — and a
            // transport that is shutting down would be redialled.
            try Task.checkCancellation()

            logger.debug("✓ SSE event stream completed", metadata: ["eventsProcessed": "\(eventCount)", "hadData": "\(hadDataEvent)"])
            return hadDataEvent
        }
    #endif
}
