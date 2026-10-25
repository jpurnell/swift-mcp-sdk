import Logging

import struct Foundation.Data
import struct Foundation.Date
import class Foundation.JSONDecoder
import class Foundation.JSONEncoder

/// Model Context Protocol client
public actor Client {
    /// The client configuration
    public struct Configuration: Hashable, Codable, Sendable {
        /// The default configuration.
        public static let `default` = Configuration(strict: false)

        /// The strict configuration.
        public static let strict = Configuration(strict: true)

        /// When strict mode is enabled, the client:
        /// - Requires server capabilities to be initialized before making requests
        /// - Rejects all requests that require capabilities before initialization
        ///
        /// While the MCP specification requires servers to respond to initialize requests
        /// with their capabilities, some implementations may not follow this.
        /// Disabling strict mode allows the client to be more lenient with non-compliant
        /// servers, though this may lead to undefined behavior.
        public var strict: Bool

        /// Creates a client configuration.
        ///
        /// - Parameter strict: If `true`, the client refuses requests that need a server capability before
        ///   the server's capabilities are known (and when the server did not advertise the capability).
        ///   Defaults to `false`, the lenient behavior.
        public init(strict: Bool = false) {
            self.strict = strict
        }
    }

    /// Implementation information
    public struct Info: Hashable, Codable, Sendable {
        /// The client name
        public var name: String
        /// A human-readable title for display purposes
        public var title: String?
        /// The client version
        public var version: String
        /// Optional description of the client
        public var description: String?
        /// Optional website URL for the client
        public var websiteUrl: String?
        /// Optional set of sized icons for display in a user interface
        public var icons: [Icon]?

        /// Creates the implementation info a client reports to the server during `initialize`
        /// (`clientInfo`).
        ///
        /// - Parameters:
        ///   - name: The client's programmatic name.
        ///   - version: The client's version string.
        ///   - title: Optional human-readable display name.
        ///   - description: Optional description of the client.
        ///   - websiteUrl: Optional URL of the client's website.
        ///   - icons: Optional sized icons a UI may display.
        public init(
            name: String,
            version: String,
            title: String? = nil,
            description: String? = nil,
            websiteUrl: String? = nil,
            icons: [Icon]? = nil
        ) {
            self.name = name
            self.title = title
            self.version = version
            self.description = description
            self.websiteUrl = websiteUrl
            self.icons = icons
        }
    }

    /// The client capabilities
    public struct Capabilities: Hashable, Codable, Sendable {
        /// The roots capabilities
        public struct Roots: Hashable, Codable, Sendable {
            /// Whether the list of roots has changed
            public var listChanged: Bool?

            /// Creates the `roots` capability declaration.
            ///
            /// - Parameter listChanged: `true` if the client sends `notifications/roots/list_changed` when
            ///   its roots change; `nil` (the default) leaves it undeclared.
            public init(listChanged: Bool? = nil) {
                self.listChanged = listChanged
            }
        }

        /// The sampling capabilities
        public struct Sampling: Hashable, Sendable {
            /// Tools sub-capability for sampling
            public struct Tools: Hashable, Codable, Sendable {
                /// Creates the `sampling.tools` marker, which carries no options; its presence says the
                /// client supports tool use in sampling requests.
                public init() {}
            }

            /// Context sub-capability for sampling
            public struct Context: Hashable, Codable, Sendable {
                /// Creates the `sampling.context` marker, which carries no options; its presence says the
                /// client supports including MCP context in sampling requests.
                public init() {}
            }

            /// Whether tools are supported in sampling
            public var tools: Tools?
            /// Whether context is supported in sampling
            public var context: Context?

            /// Creates the `sampling` capability declaration. A bare `Sampling()` declares basic sampling
            /// support with no sub-capabilities.
            ///
            /// - Parameters:
            ///   - tools: Declares tool-use support in sampling when non-`nil`.
            ///   - context: Declares context-inclusion support in sampling when non-`nil`.
            public init(tools: Tools? = nil, context: Context? = nil) {
                self.tools = tools
                self.context = context
            }
        }

        /// The elicitation capabilities
        public struct Elicitation: Hashable, Sendable {
            /// Form-based elicitation sub-capability
            public struct Form: Hashable, Codable, Sendable {
                /// Creates the `elicitation.form` marker, which carries no options; its presence says the
                /// client supports form-based elicitation.
                public init() {}
            }

            /// URL-based elicitation sub-capability
            public struct URL: Hashable, Codable, Sendable {
                /// Creates the `elicitation.url` marker, which carries no options; its presence says the
                /// client supports URL-based elicitation.
                public init() {}
            }

            /// Whether form-based elicitation is supported
            public var form: Form?
            /// Whether URL-based elicitation is supported
            public var url: URL?

            /// Creates the `elicitation` capability declaration.
            ///
            /// - Parameters:
            ///   - form: Declares form-based elicitation; defaults to ``Form`` (declared).
            ///   - url: Declares URL-based elicitation when non-`nil`; defaults to `nil`.
            public init(form: Form? = Form(), url: URL? = nil) {
                self.form = form
                self.url = url
            }
        }

        /// Whether the client supports sampling
        public var sampling: Sampling?
        /// Whether the client supports elicitation
        public var elicitation: Elicitation?
        /// Experimental features supported by the client
        public var experimental: [String: Value]?
        /// Capability extensions declared by the client,
        /// such as MCP Apps UI extensions
        public var extensions: [String: Value]?
        /// Whether the client supports roots
        public var roots: Capabilities.Roots?

        /// Creates the capability set a client advertises to servers during `initialize`.
        ///
        /// Each parameter defaults to `nil`, meaning the capability is not declared.
        ///
        /// - Parameters:
        ///   - sampling: Declares support for server-initiated `sampling/createMessage` requests.
        ///   - elicitation: Declares support for server-initiated elicitation requests.
        ///   - experimental: Non-standard features, keyed by feature identifier.
        ///   - extensions: Optional protocol extensions (for example MCP Apps UI), keyed by extension
        ///     identifier.
        ///   - roots: Declares support for `roots/list` requests.
        public init(
            sampling: Sampling? = nil,
            elicitation: Elicitation? = nil,
            experimental: [String: Value]? = nil,
            extensions: [String: Value]? = nil,
            roots: Capabilities.Roots? = nil
        ) {
            self.sampling = sampling
            self.elicitation = elicitation
            self.experimental = experimental
            self.extensions = extensions
            self.roots = roots
        }
    }

    /// The connection to the server
    private var connection: (any Transport)?
    /// The logger for the client
    private var logger: Logger? {
        get async {
            await connection?.logger
        }
    }

    /// The client information
    private let clientInfo: Client.Info
    /// The client name
    public nonisolated var name: String { clientInfo.name }
    /// A human-readable client title
    public nonisolated var title: String? { clientInfo.title }
    /// The client version
    public nonisolated var version: String { clientInfo.version }

    /// The client capabilities
    public var capabilities: Client.Capabilities
    /// The client configuration
    public var configuration: Configuration

    /// The server capabilities
    private var serverCapabilities: Server.Capabilities?
    /// The server version
    private var serverVersion: String?
    /// The server instructions
    private var instructions: String?

    /// A dictionary of type-erased notification handlers, keyed by method name
    private var notificationHandlers: [String: [NotificationHandlerBox]] = [:]
    /// Method handlers for server-to-client requests
    private var methodHandlers: [String: RequestHandlerBox] = [:]
    /// The task for the message handling loop
    private var task: Task<Void, Never>?

    /// A dictionary of type-erased pending requests, keyed by request ID
    private var pendingRequests: [ID: AnyPendingRequest] = [:]
    // Add reusable JSON encoder/decoder
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// Creates a client. Nothing is sent until ``connect(transport:)`` is called.
    ///
    /// - Parameters:
    ///   - name: The client's name, reported to the server in `clientInfo`.
    ///   - version: The client's version string, reported to the server.
    ///   - title: Optional human-readable display name.
    ///   - description: Optional description of the client.
    ///   - websiteUrl: Optional URL of the client's website.
    ///   - icons: Optional sized icons a UI may display.
    ///   - capabilities: The capabilities to advertise to the server; defaults to none.
    ///   - configuration: Behavior options such as strict capability checking; defaults to
    ///     ``Configuration/default`` (non-strict).
    public init(
        name: String,
        version: String,
        title: String? = nil,
        description: String? = nil,
        websiteUrl: String? = nil,
        icons: [Icon]? = nil,
        capabilities: Capabilities = Capabilities(),
        configuration: Configuration = .default
    ) {
        self.clientInfo = Client.Info(
            name: name, version: version, title: title,
            description: description, websiteUrl: websiteUrl, icons: icons)
        self.capabilities = capabilities
        self.configuration = configuration
    }

    /// Connects the transport, starts the background loop that reads incoming messages, and performs the MCP
    /// `initialize` handshake automatically.
    ///
    /// Register handlers (for example ``withSamplingHandler(_:)`` or ``onNotification(_:handler:)``) before
    /// connecting if the server may send requests or notifications straight away.
    ///
    /// - Parameter transport: The transport to communicate over; its `connect()` is awaited here.
    /// - Returns: The server's `initialize` result (protocol version, capabilities, server info). Discardable.
    /// - Throws: Any error from `transport.connect()` or from the `initialize` exchange.
    @discardableResult
    public func connect(transport: any Transport) async throws -> Initialize.Result {
        self.connection = transport
        try await self.connection?.connect()

        await logger?.debug(
            "Client connected", metadata: ["name": "\(name)", "version": "\(version)"])

        // Start message handling loop (matches Server.swift — no outer repeat)
        //
        // The loop reads `transport` — the connection this call established — rather than the
        // `connection` property from inside the task. Read there it is whatever the property
        // happens to hold when the scheduler first runs the body, and a `disconnect()` landing
        // in that window made the loop return before it started, which looks exactly like a
        // connection that produced no messages.
        // Named apart from the properties they came from rather than shadowing them: a local
        // `let connection = connection` reads as a no-op, and at a glance inside the loop there
        // is no way to tell which of the two any use means.
        let activeConnection = transport
        let messageDecoder = decoder
        task = Task {
            do {
                let stream = await activeConnection.receive()
                for try await data in stream {
                    if Task.isCancelled { break }

                    switch Client.decodeIncoming(data, using: messageDecoder) {
                    case .success(.batchResponse(let batchResponse)):
                        await handleBatchResponse(batchResponse)
                    case .success(.response(let response)):
                        await handleResponse(response)
                    case .success(.request(let request)):
                        await handleIncomingRequest(request)
                    case .success(.notification(let message)):
                        await handleMessage(message)
                    case .failure(let decodingError):
                        var metadata: Logger.Metadata = ["error": "\(decodingError)"]
                        if let string = String(data: data, encoding: .utf8) {
                            metadata["message"] = .string(string)
                        }
                        if let logger = await logger {
                            logger.warning(
                                "Unexpected message received by client (not single/batch response or notification)",
                                metadata: metadata
                            )
                        }
                    }
                }
            } catch {
                if let logger = await logger {
                    logger.error(
                        "Error in message handling loop", metadata: ["error": "\(error)"])
                }
            }
            await self.logger?.debug("Client message handling loop task is terminating.")
        }

        // Register cancellation notification handler
        await self.onNotification(CancelledNotification.self) { [weak self] message in
            guard let self = self else { return }

            let requestId = message.params.requestId
            let reason = message.params.reason

            await self.logger?.debug(
                "Received cancellation notification",
                metadata: [
                    "requestId": requestId.map { "\($0)" } ?? "none",
                    "reason": reason.map { "\($0)" } ?? "none",
                ]
            )

            // Remove the pending request and resume with cancellation error
            if let requestId = requestId,
                let pendingRequest = await self.removePendingRequest(id: requestId)
            {
                pendingRequest.resume(throwing: CancellationError())
            }
        }

        // Automatically initialize after connecting
        return try await _initialize()
    }

    /// A message received from the server, classified by shape.
    private enum IncomingMessage {
        case batchResponse([AnyResponse])
        case response(AnyResponse)
        case request(AnyRequest)
        case notification(AnyMessage)
    }

    /// Classifies raw bytes from the server by trying each message shape in turn.
    ///
    /// The shapes are probed in a fixed order (batch response, response, request,
    /// notification), so a failed probe is expected and not an error in itself. Only when
    /// every probe fails is the data unrecognizable, and the last probe's error is returned
    /// so the caller can log it.
    private static func decodeIncoming(
        _ data: Data, using decoder: JSONDecoder
    ) -> Result<IncomingMessage, any Error> {
        if case .success(let batch) = Result(catching: { try decoder.decode([AnyResponse].self, from: data) }) {
            return .success(.batchResponse(batch))
        }
        if case .success(let response) = Result(catching: { try decoder.decode(AnyResponse.self, from: data) }) {
            return .success(.response(response))
        }
        if case .success(let request) = Result(catching: { try decoder.decode(AnyRequest.self, from: data) }) {
            return .success(.request(request))
        }
        return Result(catching: { try decoder.decode(AnyMessage.self, from: data) })
            .map(IncomingMessage.notification)
    }

    /// Disconnects from the server: fails every in-flight request with ``MCPError`` (internal error,
    /// "Client disconnected"), cancels the receive loop, disconnects the transport, and waits for the loop to
    /// finish. Does nothing harmful if the client is not connected.
    public func disconnect() async {
        await logger?.debug("Initiating client disconnect...")

        // Part 1: Inside actor - Grab state and clear internal references
        let taskToCancel = self.task
        let connectionToDisconnect = self.connection
        let pendingRequestsToCancel = self.pendingRequests

        self.task = nil
        self.connection = nil
        self.pendingRequests = [:]  // Use empty dictionary literal

        // Part 2: Outside actor - Resume continuations, disconnect transport, await task

        // Resume continuations first
        for (_, request) in pendingRequestsToCancel {
            request.resume(throwing: MCPError.internalError("Client disconnected"))
        }
        await logger?.debug("Pending requests cancelled.")

        // Cancel the task
        taskToCancel?.cancel()
        await logger?.debug("Message loop task cancellation requested.")

        // Disconnect the transport *before* awaiting the task
        // This should ensure the transport stream is finished, unblocking the loop.
        if let conn = connectionToDisconnect {
            await conn.disconnect()
            await logger?.debug("Transport disconnected.")
        } else {
            await logger?.debug("No active transport connection to disconnect.")
        }

        // Await the task completion *after* transport disconnect
        _ = await taskToCancel?.value
        await logger?.debug("Client message loop task finished.")

        await logger?.debug("Client disconnect complete.")
    }

    // MARK: - Registration

    /// Registers a handler for notifications of type `N` received from the server, keyed by `N.name`.
    /// Handlers accumulate: registering again adds another handler rather than replacing earlier ones.
    ///
    /// - Parameters:
    ///   - type: The notification type to observe, for example ``ProgressNotification``.
    ///   - handler: Closure called with each received notification message.
    /// - Returns: The client itself, so registrations can be chained.
    @discardableResult
    public func onNotification<N: Notification>(
        _ type: N.Type,
        handler: @escaping @Sendable (Message<N>) async throws -> Void
    ) async -> Self {
        let handlers = notificationHandlers[N.name, default: []]
        notificationHandlers[N.name] = handlers + [TypedNotificationHandler(handler)]
        return self
    }

    /// Registers the handler for server-initiated requests of method type `M`, keyed by `M.name`.
    /// Registering again for the same method replaces the earlier handler.
    ///
    /// - Parameters:
    ///   - type: The method type to handle.
    ///   - handler: Closure that receives the decoded parameters and returns the result, or throws to produce
    ///     an error response.
    /// - Returns: The client itself, so registrations can be chained.
    @discardableResult
    public func withMethodHandler<M: Method>(
        _ type: M.Type,
        handler: @escaping @Sendable (M.Parameters) async throws -> M.Result
    ) -> Self {
        methodHandlers[M.name] = TypedRequestHandler { (request: Request<M>) -> Response<M> in
            let result = try await handler(request.params)
            return Response(id: request.id, result: result)
        }
        return self
    }

    /// Encodes `notification` as JSON and sends it to the server.
    ///
    /// - Parameter notification: The notification to send.
    /// - Throws: ``MCPError`` (internal error) if the client has no connection; otherwise any encoding or
    ///   transport error.
    public func notify<N: Notification>(_ notification: Message<N>) async throws {
        guard let connection = connection else {
            throw MCPError.internalError("Client connection not initialized")
        }

        let notificationData = try encoder.encode(notification)
        try await connection.send(notificationData)
    }

    /// Send a response back to the server for a server-to-client request
    private func send<M: Method>(_ response: Response<M>) async throws {
        guard let connection = connection else {
            throw MCPError.internalError("Client connection not initialized")
        }
        let responseData = try encoder.encode(response)
        try await connection.send(responseData)
    }

    // MARK: - Requests

    /// Send a request and return a RequestContext that wraps both the request ID and the Task.
    ///
    /// This allows you to track and cancel the request by sending a CancelledNotification
    /// to the server using the requestID.
    ///
    /// Example:
    /// ```swift
    /// func pingWithCancellation(client: Client) async throws {
    ///     let context = try await client.send(Ping.request())
    ///     // Later, to cancel:
    ///     try await client.cancelRequest(context.requestID, reason: "User cancelled")
    ///     // Await the result:
    ///     _ = try await context.value
    /// }
    /// ```
    ///
    /// - Parameter request: The request to send
    /// - Returns: A RequestContext containing the request ID and Task
    /// - Throws: MCPError if the client is not connected
    /// - SeeAlso: https://modelcontextprotocol.io/specification/2025-11-25/basic/utilities/cancellation
    public func send<M: Method>(_ request: Request<M>) throws -> RequestContext<M.Result> {
        guard let connection = connection else {
            throw MCPError.internalError("Client connection not initialized")
        }

        let requestData = try encoder.encode(request)

        // Registered before the send, synchronously, on the actor. The comment here used to say
        // "before attempting to send" while doing it inside a nested task the scheduler was free
        // to run after the send had completed and the response had already arrived — at which
        // point the response had nowhere to go.
        let response = Task<M.Result, Error> {
            try await withCheckedThrowingContinuation { continuation in
                addPendingRequest(id: request.id, continuation: continuation, type: M.Result.self)
            }
        }

        let requestTask = Task<M.Result, Error> {
            do {
                try await connection.send(requestData)
            } catch {
                if let logger = await logger {
                    logger.error(
                        "Failed to send request",
                        metadata: ["id": "\(request.id)", "error": "\(error)"])
                }
                // The pending entry carries its own continuation, so the failure path resumes
                // through it and the send can live here rather than in a second, nested task.
                // `nil` means the response arrived first and the entry is already gone.
                if let pending = removePendingRequest(id: request.id) {
                    pending.resume(throwing: error)
                }
            }
            return try await response.value
        }

        return RequestContext(requestID: request.id, requestTask: requestTask)
    }

    /// Cancel a request by sending a CancelledNotification to the server.
    ///
    /// According to the MCP specification, cancellation is advisory:
    /// - The server SHOULD stop processing and free resources
    /// - The server MAY ignore the cancellation if the request is unknown, already completed,
    ///   or cannot be cancelled
    /// - The client SHOULD ignore any response that arrives after cancellation
    ///
    /// This method removes the pending request and resumes it with CancellationError,
    /// ensuring that any response arriving after cancellation is ignored.
    ///
    /// - Parameters:
    ///   - requestID: The ID of the request to cancel
    ///   - reason: An optional human-readable reason for the cancellation
    /// - Throws: MCPError if the notification cannot be sent
    /// - SeeAlso: https://modelcontextprotocol.io/specification/2025-11-25/basic/utilities/cancellation
    public func cancelRequest(_ requestID: ID, reason: String? = nil) async throws {
        // Remove the pending request and resume with cancellation error
        // This ensures any response that arrives after cancellation is ignored
        if let pendingRequest = removePendingRequest(id: requestID) {
            pendingRequest.resume(throwing: CancellationError())
        }

        // Send cancellation notification to server
        let notification = CancelledNotification.message(
            .init(requestId: requestID, reason: reason)
        )
        try await notify(notification)
    }

    /// Send a request and receive its response immediately.
    ///
    /// Internal convenience method for cases where cancellation tracking is not needed.
    ///
    /// - Parameter request: The request to send
    /// - Returns: The result of the request
    /// - Throws: MCPError if the client is not connected
    func sendAndAwait<M: Method>(_ request: Request<M>) async throws -> M.Result {
        let context = try send(request)
        return try await context.value
    }

    private func addPendingRequest<T: Sendable & Decodable>(
        id: ID,
        continuation: CheckedContinuation<T, Swift.Error>,
        type: T.Type  // Keep type for AnyPendingRequest internal logic
    ) {
        pendingRequests[id] = AnyPendingRequest(
            PendingRequest(continuation: continuation)
        )
    }

    private func removePendingRequest(id: ID) -> AnyPendingRequest? {
        return pendingRequests.removeValue(forKey: id)
    }

    // MARK: - Batching

    /// A batch of requests.
    ///
    /// Objects of this type are passed as an argument to the closure
    /// of the ``Client/withBatch(body:)`` method.
    public actor Batch {
        /// The client this batch will be sent through.
        ///
        /// Weak rather than `unowned`: `addRequest` registers its pending request from a
        /// detached `Task`, which can outlive the `withBatch` scope, and `unowned` turns a
        /// client released in that window into a crash. Held weakly, the same window resumes
        /// the caller's continuation with an error it can act on.
        weak var client: Client?
        var requests: [AnyRequest] = []

        init(client: Client) {
            self.client = client
        }

        /// Adds a request to the batch and prepares its expected response task.
        /// The actual sending happens when the `withBatch` scope completes.
        /// - Returns: A `Task` that will eventually produce the result or throw an error.
        public func addRequest<M: Method>(_ request: Request<M>) async throws -> Task<
            M.Result, Swift.Error
        > {
            requests.append(try AnyRequest(request))

            // Return a Task that registers the pending request and awaits its result.
            // The continuation is resumed when the response arrives.
            return Task<M.Result, Swift.Error> {
                try await withCheckedThrowingContinuation { continuation in
                    // We are already inside a Task, but need another Task
                    // to bridge to the client actor's context.
                    Task { [weak client] in
                        guard let client else {
                            continuation.resume(throwing: MCPError.connectionClosed)
                            return
                        }
                        await client.addPendingRequest(
                            id: request.id,
                            continuation: continuation,
                            type: M.Result.self
                        )
                    }
                }
            }
        }
    }

    /// Executes multiple requests in a single batch.
    ///
    /// This method allows you to group multiple MCP requests together,
    /// which are then sent to the server as a single JSON array.
    /// The server processes these requests and sends back a corresponding
    /// JSON array of responses.
    ///
    /// Within the `body` closure, use the provided `Batch` actor to add
    /// requests using `batch.addRequest(_:)`. Each call to `addRequest`
    /// returns a `Task` handle representing the asynchronous operation
    /// for that specific request's result.
    ///
    /// It's recommended to collect these `Task` handles into an array
    /// within the `body` closure`. After the `withBatch` method returns
    /// (meaning the batch request has been sent), you can then process
    /// the results by awaiting each `Task` in the collected array.
    ///
    /// Example 1: Batching multiple tool calls and collecting typed tasks:
    /// ```swift
    /// // A small actor to hold the task handles for each tool call
    /// actor ToolTasks {
    ///     var tasks: [Task<CallTool.Result, Error>] = []
    ///     func append(_ task: Task<CallTool.Result, Error>) { tasks.append(task) }
    /// }
    ///
    /// func squareBatch(client: Client) async throws {
    ///     let collected = ToolTasks()
    ///     try await client.withBatch { batch in
    ///         for i in 0..<10 {
    ///             let task = try await batch.addRequest(
    ///                 CallTool.request(.init(name: "square", arguments: ["n": .int(i)]))
    ///             )
    ///             await collected.append(task)
    ///         }
    ///     }
    ///
    ///     // Process results after the batch is sent
    ///     let toolTasks = await collected.tasks
    ///     print("Processing \(toolTasks.count) tool results...")
    ///     for (index, task) in toolTasks.enumerated() {
    ///         do {
    ///             let result = try await task.value
    ///             print("\(index): \(result.content)")
    ///         } catch {
    ///             print("\(index) failed: \(error)")
    ///         }
    ///     }
    /// }
    /// ```
    ///
    /// Example 2: Batching different request types and awaiting individual tasks:
    /// ```swift
    /// // A small actor to hold the task handles created inside the batch closure
    /// actor BatchTasks {
    ///     var ping: Task<Ping.Result, Error>?
    ///     var prompt: Task<GetPrompt.Result, Error>?
    ///     func set(ping: Task<Ping.Result, Error>, prompt: Task<GetPrompt.Result, Error>) {
    ///         self.ping = ping
    ///         self.prompt = prompt
    ///     }
    /// }
    ///
    /// func pingAndGreet(client: Client) async throws {
    ///     let collected = BatchTasks()
    ///
    ///     try await client.withBatch { batch in
    ///         let ping = try await batch.addRequest(Ping.request())
    ///         let prompt = try await batch.addRequest(GetPrompt.request(.init(name: "greeting")))
    ///         await collected.set(ping: ping, prompt: prompt)
    ///     }
    ///
    ///     // Await the results after the batch is sent
    ///     do {
    ///         if let pingTask = await collected.ping {
    ///             _ = try await pingTask.value  // Throws if the ping failed
    ///             print("Ping successful")
    ///         }
    ///         if let promptTask = await collected.prompt {
    ///             let promptResult = try await promptTask.value
    ///             print("Prompt description: \(promptResult.description ?? "None")")
    ///         }
    ///     } catch {
    ///         print("Error processing batch results: \(error)")
    ///     }
    /// }
    /// ```
    ///
    /// - Parameter body: An asynchronous closure that takes a `Batch` object as input.
    ///                   Use this object to add requests to the batch.
    /// - Throws: `MCPError.internalError` if the client is not connected.
    ///           Can also rethrow errors from the `body` closure or from sending the batch request.
    public func withBatch(body: @escaping @Sendable (Batch) async throws -> Void) async throws {
        guard let connection = connection else {
            throw MCPError.internalError("Client connection not initialized")
        }

        // Create Batch actor, passing self (Client)
        let batch = Batch(client: self)

        // Populate the batch actor by calling the user's closure.
        try await body(batch)

        // Get the collected requests from the batch actor
        let requests = await batch.requests

        // Check if there are any requests to send
        guard !requests.isEmpty else {
            await logger?.debug("Batch requested but no requests were added.")
            return  // Nothing to send
        }

        await logger?.debug(
            "Sending batch request", metadata: ["count": "\(requests.count)"])

        // Encode the array of AnyMethod requests into a single JSON payload
        let data = try encoder.encode(requests)
        try await connection.send(data)

        // Responses will be handled asynchronously by the message loop and handleBatchResponse/handleResponse.
    }

    // MARK: - Lifecycle

    /// Initialize the connection with the server.
    ///
    /// - Important: This method is deprecated. Initialization now happens automatically
    ///   when calling `connect(transport:)`. You should use that method instead.
    ///
    /// - Returns: The server's initialization response containing capabilities and server info
    @available(
        *, deprecated,
        message:
            "Initialization now happens automatically during connect. Use connect(transport:) instead."
    )
    public func initialize() async throws -> Initialize.Result {
        return try await _initialize()
    }

    /// Internal initialization implementation
    private func _initialize() async throws -> Initialize.Result {
        let request = Initialize.request(
            .init(
                protocolVersion: Version.latest,
                capabilities: capabilities,
                clientInfo: clientInfo
            ))

        let result = try await sendAndAwait(request)

        self.serverCapabilities = result.capabilities
        self.serverVersion = result.protocolVersion
        self.instructions = result.instructions

        // For HTTP transport, ensure subsequent MCP-Protocol-Version headers
        // reflect the negotiated lifecycle version.
        if let httpTransport = connection as? HTTPClientTransport {
            await httpTransport.updateNegotiatedProtocolVersion(result.protocolVersion)
        }

        try await notify(InitializedNotification.message())

        return result
    }

    /// Sends a `ping` request and waits for the server to respond.
    ///
    /// Use this to verify that the connection is alive and the server is responsive.
    ///
    /// - Throws: ``MCPError`` if the client is not connected or the server returns an error.
    /// - SeeAlso: https://modelcontextprotocol.io/specification/2025-11-25/basic/utilities/ping
    public func ping() async throws {
        let request = Ping.request()
        _ = try await sendAndAwait(request)
    }

    // MARK: - Prompts

    /// Retrieves a prompt from the server, filling in its arguments.
    ///
    /// - Parameters:
    ///   - name: The name of the prompt to retrieve.
    ///   - arguments: Values for the prompt's arguments, keyed by argument name.
    /// - Returns: The prompt's optional description and its rendered messages.
    /// - Throws: ``MCPError`` if the server does not advertise the `prompts` capability (in strict mode), the client is not connected, or the server returns an error.
    /// - SeeAlso: https://modelcontextprotocol.io/specification/2025-11-25/server/prompts
    public func getPrompt(name: String, arguments: [String: String]? = nil) async throws
        -> (description: String?, messages: [Prompt.Message])
    {
        try validateServerCapability(\.prompts, "Prompts")
        let request = GetPrompt.request(.init(name: name, arguments: arguments))
        let result = try await sendAndAwait(request)
        return (description: result.description, messages: result.messages)
    }

    /// Lists the prompts the server offers.
    ///
    /// - Parameter cursor: An opaque pagination cursor from a previous call's `nextCursor`, or `nil` for the first page.
    /// - Returns: The prompts on this page and a cursor for the next page, or `nil` if there are no more.
    /// - Throws: ``MCPError`` if the server does not advertise the `prompts` capability (in strict mode), the client is not connected, or the server returns an error.
    /// - SeeAlso: https://modelcontextprotocol.io/specification/2025-11-25/server/prompts
    public func listPrompts(cursor: String? = nil) async throws
        -> (prompts: [Prompt], nextCursor: String?)
    {
        try validateServerCapability(\.prompts, "Prompts")
        let request: Request<ListPrompts>
        if let cursor = cursor {
            request = ListPrompts.request(.init(cursor: cursor))
        } else {
            request = ListPrompts.request(.init())
        }
        let result = try await sendAndAwait(request)
        return (prompts: result.prompts, nextCursor: result.nextCursor)
    }

    // MARK: - Resources

    /// Reads the contents of a resource from the server.
    ///
    /// - Parameter uri: The URI of the resource to read.
    /// - Returns: The contents of the resource. A single URI may yield several content items.
    /// - Throws: ``MCPError`` if the server does not advertise the `resources` capability (in strict mode), the client is not connected, or the server returns an error.
    /// - SeeAlso: https://modelcontextprotocol.io/specification/2025-11-25/server/resources
    public func readResource(uri: String) async throws -> [Resource.Content] {
        try validateServerCapability(\.resources, "Resources")
        let request = ReadResource.request(.init(uri: uri))
        let result = try await sendAndAwait(request)
        return result.contents
    }

    /// Lists the resources the server offers.
    ///
    /// - Parameter cursor: An opaque pagination cursor from a previous call's `nextCursor`, or `nil` for the first page.
    /// - Returns: The resources on this page and a cursor for the next page, or `nil` if there are no more.
    /// - Throws: ``MCPError`` if the server does not advertise the `resources` capability (in strict mode), the client is not connected, or the server returns an error.
    /// - SeeAlso: https://modelcontextprotocol.io/specification/2025-11-25/server/resources
    public func listResources(cursor: String? = nil) async throws -> (
        resources: [Resource], nextCursor: String?
    ) {
        try validateServerCapability(\.resources, "Resources")
        let request: Request<ListResources>
        if let cursor = cursor {
            request = ListResources.request(.init(cursor: cursor))
        } else {
            request = ListResources.request(.init())
        }
        let result = try await sendAndAwait(request)
        return (resources: result.resources, nextCursor: result.nextCursor)
    }

    /// Subscribes to change notifications for a resource.
    ///
    /// The server sends `notifications/resources/updated` when the resource changes.
    ///
    /// - Parameter uri: The URI of the resource to subscribe to.
    /// - Throws: ``MCPError`` if the server does not advertise resource subscriptions (in strict mode), the client is not connected, or the server returns an error.
    /// - SeeAlso: https://modelcontextprotocol.io/specification/2025-11-25/server/resources#subscriptions
    public func subscribeToResource(uri: String) async throws {
        try validateServerCapability(\.resources?.subscribe, "Resource subscription")
        let request = ResourceSubscribe.request(.init(uri: uri))
        _ = try await sendAndAwait(request)
    }

    /// Lists the resource templates the server offers.
    ///
    /// Resource templates are URI templates (RFC 6570) describing families of resources.
    ///
    /// - Parameter cursor: An opaque pagination cursor from a previous call's `nextCursor`, or `nil` for the first page.
    /// - Returns: The templates on this page and a cursor for the next page, or `nil` if there are no more.
    /// - Throws: ``MCPError`` if the server does not advertise the `resources` capability (in strict mode), the client is not connected, or the server returns an error.
    /// - SeeAlso: https://modelcontextprotocol.io/specification/2025-11-25/server/resources#resource-templates
    public func listResourceTemplates(cursor: String? = nil) async throws -> (
        templates: [Resource.Template], nextCursor: String?
    ) {
        try validateServerCapability(\.resources, "Resources")
        let request: Request<ListResourceTemplates>
        if let cursor = cursor {
            request = ListResourceTemplates.request(.init(cursor: cursor))
        } else {
            request = ListResourceTemplates.request(.init())
        }
        let result = try await sendAndAwait(request)
        return (templates: result.templates, nextCursor: result.nextCursor)
    }

    // MARK: - Tools

    /// Lists the tools the server offers.
    ///
    /// - Parameter cursor: An opaque pagination cursor from a previous call's `nextCursor`, or `nil` for the first page.
    /// - Returns: The tools on this page and a cursor for the next page, or `nil` if there are no more.
    /// - Throws: ``MCPError`` if the server does not advertise the `tools` capability (in strict mode), the client is not connected, or the server returns an error.
    /// - SeeAlso: https://modelcontextprotocol.io/specification/2025-11-25/server/tools
    public func listTools(cursor: String? = nil) async throws -> (
        tools: [Tool], nextCursor: String?
    ) {
        try validateServerCapability(\.tools, "Tools")
        let request: Request<ListTools>
        if let cursor = cursor {
            request = ListTools.request(.init(cursor: cursor))
        } else {
            request = ListTools.request(.init())
        }
        let result = try await sendAndAwait(request)
        return (tools: result.tools, nextCursor: result.nextCursor)
    }

    /// Call a tool on the server.
    ///
    /// - Parameters:
    ///   - name: The name of the tool to call.
    ///   - arguments: Arguments to use for the tool call.
    ///   - meta: Optional request metadata including progress token. If `progressToken` is specified,
    ///           the caller is requesting out-of-band progress notifications for this request.
    ///           Use `onNotification(ProgressNotification.self)` to receive progress updates.
    /// - Returns: A tuple containing the tool's content response and an optional error flag.
    /// - Note: For advanced use cases requiring cancellation support, use `send()` directly to get a `RequestContext`.
    /// - SeeAlso: https://modelcontextprotocol.io/specification/2025-11-25/server/tools/#calling-tools
    public func callTool(
        name: String,
        arguments: [String: Value]? = nil,
        meta: Metadata? = nil
    ) async throws -> (content: [Tool.Content], isError: Bool?) {
        try validateServerCapability(\.tools, "Tools")
        let request = CallTool.request(.init(name: name, arguments: arguments, meta: meta))
        let result = try await sendAndAwait(request)
        return (content: result.content, isError: result.isError)
    }

    /// Call a tool on the server.
    ///
    /// - Parameters:
    ///   - name: The name of the tool to call.
    ///   - arguments: Arguments to use for the tool call.
    ///   - meta: Optional request metadata including progress token. If `progressToken` is specified,
    ///           the caller is requesting out-of-band progress notifications for this request.
    ///           Use `onNotification(ProgressNotification.self)` to receive progress updates.
    /// - Returns: A tuple containing the tool's content response and an optional error flag.
    /// - Note: For advanced use cases requiring cancellation support, use `send()` directly to get a `RequestContext`.
    /// - SeeAlso: https://modelcontextprotocol.io/specification/2025-11-25/server/tools/#calling-tools
    public func callTool(
        name: String,
        arguments: [String: Value]? = nil,
        meta: Metadata? = nil
    ) throws -> RequestContext<CallTool.Result> {
        try validateServerCapability(\.tools, "Tools")
        let request = CallTool.request(.init(name: name, arguments: arguments, meta: meta))
        return try send(request)
    }

    // MARK: - Sampling

    /// Register a handler for sampling requests from servers
    ///
    /// Sampling allows servers to request LLM completions through the client,
    /// enabling sophisticated agentic behaviors while maintaining human-in-the-loop control.
    ///
    /// The sampling flow follows these steps:
    /// 1. Server sends a `sampling/createMessage` request to the client
    /// 2. Client reviews the request and can modify it (via this handler)
    /// 3. Client samples from an LLM (via this handler)
    /// 4. Client reviews the completion (via this handler)
    /// 5. Client returns the result to the server
    ///
    /// - Parameter handler: A closure that processes sampling requests and returns completions
    /// - Returns: Self for method chaining
    /// - SeeAlso: https://modelcontextprotocol.io/docs/concepts/sampling#how-sampling-works
    @discardableResult
    public func withSamplingHandler(
        _ handler:
            @escaping @Sendable (CreateSamplingMessage.Parameters) async throws ->
            CreateSamplingMessage.Result
    ) -> Self {
        return withMethodHandler(CreateSamplingMessage.self, handler: handler)
    }

    // MARK: - Elicitation

    /// Register a handler for elicitation requests from servers
    ///
    /// The elicitation flow lets servers collect structured input from users during
    /// ongoing interactions. Clients remain in control by mediating the prompt,
    /// collecting the response, and returning the chosen action to the server.
    ///
    /// - Parameter handler: A closure that processes elicitation requests and returns user actions
    /// - Returns: Self for method chaining
    /// - SeeAlso: https://modelcontextprotocol.io/specification/2025-06-18/client/elicitation
    @discardableResult
    public func withElicitationHandler(
        _ handler:
            @escaping @Sendable (CreateElicitation.Parameters) async throws ->
            CreateElicitation.Result
    ) -> Self {
        return withMethodHandler(CreateElicitation.self, handler: handler)
    }

    // MARK: - Roots

    /// Register a handler for roots/list requests from servers
    ///
    /// Roots define filesystem boundaries that servers can operate within.
    /// Unlike other MCP features, roots use bidirectional communication where
    /// servers send requests TO clients to discover available roots.
    ///
    /// - Parameter handler: A closure that returns the list of available roots
    /// - Returns: Self for method chaining
    /// - SeeAlso: https://modelcontextprotocol.io/specification/2025-11-25/client/roots
    @discardableResult
    public func withRootsHandler(
        _ handler: @escaping @Sendable () async throws -> [Root]
    ) -> Self {
        return withMethodHandler(ListRoots.self) { _ in
            let roots = try await handler()
            return ListRoots.Result(roots: roots)
        }
    }

    /// Notify the server that the list of roots has changed
    ///
    /// Clients should send this notification when roots are added, removed,
    /// or modified to inform connected servers of the change.
    ///
    /// - Throws: MCPError if the client is not connected
    /// - SeeAlso: https://modelcontextprotocol.io/specification/2025-11-25/client/roots
    public func notifyRootsChanged() async throws {
        let notification = RootsListChangedNotification.message()
        try await notify(notification)
    }

    // MARK: - Logging

    /// Set the minimum logging level for server log messages.
    ///
    /// Servers that declare the `logging` capability will send log messages via
    /// `notifications/message` notifications. Use this method to control which
    /// severity levels the server should send.
    ///
    /// - Parameter level: The minimum log level to receive
    /// - Throws: MCPError if the client is not connected or if the server doesn't support logging
    /// - SeeAlso: https://modelcontextprotocol.io/specification/2025-11-25/server/utilities/logging/
    public func setLoggingLevel(_ level: LogLevel) async throws {
        try validateServerCapability(\.logging, "Logging")
        let request = SetLoggingLevel.request(.init(level: level))
        _ = try await sendAndAwait(request)
    }

    // MARK: - Completions

    /// Request completion suggestions for a prompt argument.
    ///
    /// Servers that declare the `completions` capability can provide autocompletion
    /// suggestions for prompt arguments as users type.
    ///
    /// - Parameters:
    ///   - promptName: The name of the prompt
    ///   - argumentName: The name of the argument being completed
    ///   - argumentValue: The current (partial) value of the argument
    ///   - context: Optional context with already-resolved arguments
    /// - Returns: A completion result containing suggested values
    /// - Throws: MCPError if the client is not connected or if the server doesn't support completions
    /// - SeeAlso: https://modelcontextprotocol.io/specification/2025-11-25/server/utilities/completion/
    public func complete(
        promptName: String,
        argumentName: String,
        argumentValue: String,
        context: [String: String]? = nil
    ) async throws -> Complete.Result.Completion {
        try validateServerCapability(\.completions, "Completions")
        let request = Complete.request(
            .init(
                ref: .prompt(.init(name: promptName)),
                argument: .init(name: argumentName, value: argumentValue),
                context: context.map { .init(arguments: $0) }
            )
        )
        let result = try await sendAndAwait(request)
        return result.completion
    }

    /// Request completion suggestions for a resource template argument.
    ///
    /// Servers that declare the `completions` capability can provide autocompletion
    /// suggestions for resource template arguments as users type.
    ///
    /// - Parameters:
    ///   - resourceURI: The URI of the resource template
    ///   - argumentName: The name of the argument being completed
    ///   - argumentValue: The current (partial) value of the argument
    ///   - context: Optional context with already-resolved arguments
    /// - Returns: A completion result containing suggested values
    /// - Throws: MCPError if the client is not connected or if the server doesn't support completions
    /// - SeeAlso: https://modelcontextprotocol.io/specification/2025-11-25/server/utilities/completion/
    public func complete(
        resourceURI: String,
        argumentName: String,
        argumentValue: String,
        context: [String: String]? = nil
    ) async throws -> Complete.Result.Completion {
        try validateServerCapability(\.completions, "Completions")
        let request = Complete.request(
            .init(
                ref: .resource(.init(uri: resourceURI)),
                argument: .init(name: argumentName, value: argumentValue),
                context: context.map { .init(arguments: $0) }
            )
        )
        let result = try await sendAndAwait(request)
        return result.completion
    }

    // MARK: -

    private func handleResponse(_ response: Response<AnyMethod>) async {
        await logger?.trace(
            "Processing response",
            metadata: ["id": "\(response.id)"])

        // Attempt to remove the pending request using the response ID.
        // Resume with the response only if it hadn't yet been removed.
        if let removedRequest = self.removePendingRequest(id: response.id) {
            // If we successfully removed it, resume its continuation.
            switch response.result {
            case .success(let value):
                removedRequest.resume(returning: value)
            case .failure(let error):
                removedRequest.resume(throwing: error)
            }
        } else {
            // Request was already removed (e.g., by send error handler or disconnect).
            // Log this, but it's not an error in race condition scenarios.
            await logger?.warning(
                "Attempted to handle response for already removed request",
                metadata: ["id": "\(response.id)"]
            )
        }
    }

    private func handleMessage(_ message: Message<AnyNotification>) async {
        await logger?.trace(
            "Processing notification",
            metadata: ["method": "\(message.method)"])

        // Find notification handlers for this method
        guard let handlers = notificationHandlers[message.method] else { return }

        // Convert notification parameters to concrete type and call handlers
        for handler in handlers {
            do {
                try await handler(message)
            } catch {
                if let logger = await logger {
                    logger.error(
                        "Error handling notification",
                        metadata: [
                            "method": "\(message.method)",
                            "error": "\(error)",
                        ])
                }
            }
        }
    }

    private func handleIncomingRequest(_ request: Request<AnyMethod>) async {
        await logger?.trace(
            "Processing incoming request from server",
            metadata: ["method": "\(request.method)", "id": "\(request.id)"])

        guard let handler = methodHandlers[request.method] else {
            await logger?.warning(
                "No handler registered for method",
                metadata: ["method": "\(request.method)"])
            let error = MCPError.methodNotFound("Unknown method: \(request.method)")
            let response = AnyMethod.response(id: request.id, error: error)
            do {
                try await send(response)
            } catch {
                if let logger = await logger {
                    logger.error(
                        "Failed to send error response",
                        metadata: ["error": "\(error)"])
                }
            }
            return
        }

        do {
            let response = try await handler(request)
            try await send(response)
        } catch {
            if let logger = await logger {
                logger.error(
                    "Handler for server request failed",
                    metadata: ["method": "\(request.method)", "error": "\(error)"])
            }
            let mcpError = error as? MCPError ?? MCPError.internalError(error.localizedDescription)
            let response = AnyMethod.response(id: request.id, error: mcpError)
            do {
                try await send(response)
            } catch {
                if let logger = await logger {
                    logger.error(
                        "Failed to send error response",
                        metadata: ["error": "\(error)"])
                }
            }
        }
    }

    // MARK: -

    /// Validate the server capabilities.
    /// Throws an error if the client is configured to be strict and the capability is not supported.
    private func validateServerCapability<T>(
        _ keyPath: KeyPath<Server.Capabilities, T?>,
        _ name: String
    )
        throws
    {
        if configuration.strict {
            guard let capabilities = serverCapabilities else {
                throw MCPError.methodNotFound("Server capabilities not initialized")
            }
            guard capabilities[keyPath: keyPath] != nil else {
                throw MCPError.methodNotFound("\(name) is not supported by the server")
            }
        }
    }

    // Add handler for batch responses
    private func handleBatchResponse(_ responses: [AnyResponse]) async {
        await logger?.trace("Processing batch response", metadata: ["count": "\(responses.count)"])
        for response in responses {
            // Attempt to remove the pending request.
            // If successful, pendingRequest contains the request.
            if let pendingRequest = self.removePendingRequest(id: response.id) {
                // If we successfully removed it, handle the response using the pending request.
                switch response.result {
                case .success(let value):
                    pendingRequest.resume(returning: value)
                case .failure(let error):
                    pendingRequest.resume(throwing: error)
                }
            } else {
                // If removal failed, it means the request ID was not found (or already handled).
                // Log a warning.
                await logger?.warning(
                    "Received response in batch for unknown or already handled request ID",
                    metadata: ["id": "\(response.id)"]
                )
            }
        }
    }
}

// MARK: - Codable

extension Client.Capabilities.Sampling: Codable {
    private enum CodingKeys: String, CodingKey {
        case tools, context
    }

    /// Decodes the `sampling` capability object. Both keys are optional: `tools` and `context` are each
    /// decoded if present, so an empty object (`{}`) yields a value with no sub-capabilities.
    ///
    /// - Throws: `DecodingError` if a present key has the wrong shape.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.tools = try container.decodeIfPresent(Tools.self, forKey: .tools)
        self.context = try container.decodeIfPresent(Context.self, forKey: .context)
    }

    /// Encodes the `sampling` capability object, writing `tools` and `context` only when set. With neither
    /// set the output is an empty object `{}`.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(tools, forKey: .tools)
        try container.encodeIfPresent(context, forKey: .context)
    }
}

extension Client.Capabilities.Elicitation: Codable {
    private enum CodingKeys: String, CodingKey {
        case form, url
    }

    /// Decodes the `elicitation` capability object. `form` and `url` are both optional, but if neither is
    /// present (including for an empty object `{}`) `form` is set to a default ``Form``, preserving the
    /// pre-`url` meaning of an empty elicitation capability.
    ///
    /// - Throws: `DecodingError` if a present key has the wrong shape.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.form = try container.decodeIfPresent(Form.self, forKey: .form)
        self.url = try container.decodeIfPresent(URL.self, forKey: .url)
        // If both are nil, default to form for backward compatibility
        if self.form == nil && self.url == nil {
            self.form = Form()
        }
    }

    /// Encodes the `elicitation` capability object, writing `form` and `url` only when set. With neither set
    /// the output is `{}`, which a decoder reads back as form support.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(form, forKey: .form)
        try container.encodeIfPresent(url, forKey: .url)
    }
}
