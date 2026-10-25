import Foundation
import Logging

#if canImport(Network)
    import Network

    /// Protocol that abstracts the Network.NWConnection functionality needed for NetworkTransport
    @preconcurrency protocol NetworkConnectionProtocol {
        var state: NWConnection.State { get }
        var stateUpdateHandler: ((@Sendable (NWConnection.State) -> Void))? { get set }

        func start(queue: DispatchQueue)
        func cancel()
        func send(
            content: Data?, contentContext: NWConnection.ContentContext, isComplete: Bool,
            completion: NWConnection.SendCompletion)
        func receive(
            minimumIncompleteLength: Int, maximumLength: Int,
            completion: @escaping @Sendable (
                Data?, NWConnection.ContentContext?, Bool, NWError?
            ) -> Void)
    }

    /// Extension to conform NWConnection to internal NetworkConnectionProtocol
    extension NWConnection: NetworkConnectionProtocol {}

    /// An implementation of a custom MCP transport using Apple's Network framework.
    ///
    /// This transport allows MCP clients and servers to communicate over TCP/UDP connections
    /// using Apple's Network framework.
    ///
    /// - Important: This transport is available exclusively on Apple platforms
    ///   (macOS, iOS, watchOS, tvOS, visionOS) as it depends on the Network framework.
    ///
    /// ## Example Usage
    ///
    /// ```swift
    /// import MCP
    /// import Network
    ///
    /// // Create a TCP connection to a server
    /// let connection = NWConnection(
    ///     host: NWEndpoint.Host("localhost"),
    ///     port: 8080,
    ///     using: .tcp
    /// )
    ///
    /// // Initialize the transport with the connection
    /// let transport = NetworkTransport(connection: connection)
    ///
    /// // For large messages (e.g., images), configure unlimited buffer size
    /// let largeBufferTransport = NetworkTransport(
    ///     connection: connection,
    ///     bufferConfig: .unlimited
    /// )
    ///
    /// // Use the transport with an MCP client
    /// let client = Client(name: "MyApp", version: "1.0.0")
    /// try await client.connect(transport: transport)
    /// ```
    public actor NetworkTransport: Transport {
        /// A liveness probe exchanged between peers: a 4-byte magic prefix followed by an 8-byte little-endian
        /// timestamp in milliseconds since the Foundation reference date (12 bytes in all).
        public struct Heartbeat: RawRepresentable, Hashable, Sendable {
            /// Magic bytes used to identify a heartbeat message.
            private static let magicBytes: [UInt8] = [0xF0, 0x9F, 0x92, 0x93]

            /// The timestamp of when the heartbeat was created.
            public let timestamp: Date

            /// Creates a heartbeat stamped with the current time.
            public init() {
                self.timestamp = Date()
            }

            /// Creates a heartbeat with a specific timestamp.
            ///
            /// - Parameter timestamp: The timestamp for the heartbeat.
            public init(timestamp: Date) {
                self.timestamp = timestamp
            }

            // MARK: - RawRepresentable

            /// The raw byte representation of a heartbeat.
            public typealias RawValue = [UInt8]

            /// Creates a heartbeat from its raw representation.
            ///
            /// Bytes beyond the first 12 are ignored; millisecond precision is retained.
            ///
            /// - Parameter rawValue: The raw bytes of the heartbeat message.
            /// - Returns: A heartbeat, or `nil` if fewer than 12 bytes are given or the first four are not the
            ///   magic prefix.
            public init?(rawValue: [UInt8]) {
                // Check if the data has the correct format (magic bytes + timestamp)
                guard rawValue.count >= 12,
                    rawValue.prefix(4).elementsEqual(Self.magicBytes)
                else {
                    return nil
                }

                // Read the timestamp a byte at a time, little-endian.
                //
                // This was `withUnsafeBytes { $0.load(as: UInt64.self) }`, which had two
                // problems that only a hostile platform would have shown: `load(as:)` requires
                // the memory to be aligned for the type and a `Data` slice offers no such
                // guarantee, and it takes the host's byte order for a wire format's. Shifting
                // makes the order part of the format rather than a property of the machine —
                // and little-endian is what every platform this has run on was already
                // producing, so nothing on the wire changes.
                let timestamp = rawValue[4..<12].enumerated().reduce(UInt64(0)) { value, byte in
                    value | (UInt64(byte.element) << (8 * byte.offset))
                }

                self.timestamp = Date(
                    timeIntervalSinceReferenceDate: TimeInterval(timestamp) / 1000.0)
            }

            /// The 12-byte wire form: magic prefix then the little-endian millisecond timestamp.
            public var rawValue: [UInt8] {
                var result = Data(Self.magicBytes)

                // Add timestamp (milliseconds since reference date), little-endian, written
                // out explicitly so the format does not depend on the host. See the decoder.
                let timestamp = UInt64(self.timestamp.timeIntervalSinceReferenceDate * 1000)
                result.append(
                    contentsOf: (0..<8).map { UInt8(truncatingIfNeeded: timestamp >> (8 * $0)) })

                return Array(result)
            }

            /// The wire form (``rawValue``) as `Data`, ready to send.
            public var data: Data {
                return Data(self.rawValue)
            }

            /// Reports whether data begins with the heartbeat magic prefix.
            ///
            /// Only the first four bytes are examined, so this is cheap enough to run on every received chunk.
            ///
            /// - Parameter data: The received bytes to check.
            /// - Returns: `true` if the data is at least four bytes and starts with the magic prefix.
            public static func isHeartbeat(_ data: Data) -> Bool {
                guard data.count >= 4 else {
                    return false
                }

                return data.prefix(4).elementsEqual(Self.magicBytes)
            }

            /// Parses a heartbeat from received data.
            ///
            /// - Parameter data: The bytes to parse.
            /// - Returns: The heartbeat, or `nil` if the data is shorter than 12 bytes or lacks the magic prefix.
            public static func from(data: Data) -> Heartbeat? {
                guard data.count >= 12 else {
                    return nil
                }

                return Heartbeat(rawValue: Array(data))
            }
        }

        /// Settings for the periodic heartbeat the transport sends to detect dead connections.
        public struct HeartbeatConfiguration: Hashable, Sendable {
            /// Whether the transport sends heartbeats at all.
            public let enabled: Bool
            /// Seconds between heartbeats.
            public let interval: TimeInterval

            /// Creates a heartbeat configuration.
            ///
            /// - Parameters:
            ///   - enabled: Whether heartbeats are sent. Defaults to `true`.
            ///   - interval: Seconds between heartbeats. Defaults to 15.
            public init(enabled: Bool = true, interval: TimeInterval = 15.0) {
                self.enabled = enabled
                self.interval = interval
            }

            /// Default heartbeat configuration.
            public static let `default` = HeartbeatConfiguration()

            /// Configuration with heartbeats disabled.
            public static let disabled = HeartbeatConfiguration(enabled: false)
        }

        /// Settings for retrying a failed or lost connection with exponential backoff.
        public struct ReconnectionConfiguration: Hashable, Sendable {
            /// Whether the transport should attempt to reconnect on failure.
            public let enabled: Bool
            /// The maximum number of retries after the first connection attempt fails.
            public let maxAttempts: Int
            /// The factor each successive backoff delay is multiplied by, starting from 0.5 seconds.
            public let backoffMultiplier: Double

            /// Creates a reconnection configuration.
            ///
            /// - Parameters:
            ///   - enabled: Whether reconnection is attempted on failure. Defaults to `true`.
            ///   - maxAttempts: The maximum number of retries after the first attempt fails. Defaults to 5.
            ///   - backoffMultiplier: Growth factor applied to the 0.5 s base delay for each further attempt.
            ///     Defaults to 1.5.
            public init(
                enabled: Bool = true,
                maxAttempts: Int = 5,
                backoffMultiplier: Double = 1.5
            ) {
                self.enabled = enabled
                self.maxAttempts = maxAttempts
                self.backoffMultiplier = backoffMultiplier
            }

            /// Default reconnection configuration.
            public static let `default` = ReconnectionConfiguration()

            /// Configuration with reconnection disabled.
            public static let disabled = ReconnectionConfiguration(enabled: false)

            /// Calculates the backoff delay for a given attempt number.
            ///
            /// The delay is `0.5 * backoffMultiplier^(attempt - 1)` seconds, so attempt 1 waits 0.5 s.
            ///
            /// - Parameter attempt: The current attempt number, 1-based.
            /// - Returns: The delay in seconds before the next attempt.
            public func backoffDelay(for attempt: Int) -> TimeInterval {
                let baseDelay = 0.5  // 500ms
                return baseDelay * pow(backoffMultiplier, Double(attempt - 1))
            }
        }

        /// Limits on how much data the transport will accept from the connection in one read.
        public struct BufferConfiguration: Hashable, Sendable {
            /// The largest chunk, in bytes, requested from the connection per read; `nil` means no limit is
            /// imposed by the transport (the system default applies).
            public let maxReceiveBufferSize: Int?

            /// Creates a buffer configuration.
            ///
            /// - Parameter maxReceiveBufferSize: Largest read chunk in bytes, or `nil` for no limit. Defaults to
            ///   10 MiB (10 * 1024 * 1024).
            public init(maxReceiveBufferSize: Int? = 10 * 1024 * 1024) {
                self.maxReceiveBufferSize = maxReceiveBufferSize
            }

            /// Default buffer configuration with 10MB limit.
            public static let `default` = BufferConfiguration()

            /// Configuration with no buffer size limit.
            public static let unlimited = BufferConfiguration(maxReceiveBufferSize: nil)
        }

        // State tracking
        private var isConnected = false
        private var isStopping = false
        private var reconnectAttempt = 0
        private var heartbeatTask: Task<Void, Never>?
        private var lastHeartbeatTime: Date?
        private let messageStream: AsyncThrowingStream<Data, Swift.Error>
        private let messageContinuation: AsyncThrowingStream<Data, Swift.Error>.Continuation

        // Justification: reassigned only during connect/disconnect on the transport actor; the closures that read it run on the connection's own queue
        // Connection is marked nonisolated(unsafe) to allow access from closures
        // Justification: reassigned only during connect/disconnect on the transport actor; the closures that read it run on the connection's own queue
        private nonisolated(unsafe) var connection: NetworkConnectionProtocol

        /// The logger that receives this transport's diagnostics. A no-op logger is used if none was supplied.
        public nonisolated let logger: Logger

        // Configuration
        private let heartbeatConfig: HeartbeatConfiguration
        private let reconnectionConfig: ReconnectionConfiguration
        private let bufferConfig: BufferConfiguration

        /// Waits out a reconnection backoff. Production sleeps; tests substitute a recorder so the
        /// schedule can be asserted without real time passing.
        private let backoffSleep: @Sendable (Duration) async throws -> Void

        /// Creates a transport that exchanges newline-delimited messages over an existing `NWConnection`.
        ///
        /// The connection is not started until ``connect()`` is called, so the caller should not start it.
        ///
        /// - Parameters:
        ///   - connection: The connection to communicate over; the transport takes control of its lifecycle.
        ///   - logger: Logger for transport diagnostics. Defaults to `nil`, which discards log output.
        ///   - heartbeatConfig: Heartbeat behaviour. Defaults to ``HeartbeatConfiguration/default``.
        ///   - reconnectionConfig: Retry behaviour. Defaults to ``ReconnectionConfiguration/default``.
        ///   - bufferConfig: Receive buffer limit. Defaults to ``BufferConfiguration/default``.
        public init(
            connection: NWConnection,
            logger: Logger? = nil,
            heartbeatConfig: HeartbeatConfiguration = .default,
            reconnectionConfig: ReconnectionConfiguration = .default,
            bufferConfig: BufferConfiguration = .default
        ) {
            self.init(
                connection,
                logger: logger,
                heartbeatConfig: heartbeatConfig,
                reconnectionConfig: reconnectionConfig,
                bufferConfig: bufferConfig
            )
        }

        init(
            _ connection: NetworkConnectionProtocol,
            logger: Logger? = nil,
            heartbeatConfig: HeartbeatConfiguration = .default,
            reconnectionConfig: ReconnectionConfiguration = .default,
            bufferConfig: BufferConfiguration = .default,
            backoffSleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
        ) {
            self.backoffSleep = backoffSleep
            self.connection = connection
            self.logger =
                logger
                ?? Logger(
                    label: "mcp.transport.network",
                    factory: { _ in SwiftLogNoOpLogHandler() }
                )
            self.reconnectionConfig = reconnectionConfig
            self.heartbeatConfig = heartbeatConfig
            self.bufferConfig = bufferConfig

            // Create message stream
            var continuation: AsyncThrowingStream<Data, Swift.Error>.Continuation!
            self.messageStream = AsyncThrowingStream { continuation = $0 }
            self.messageContinuation = continuation
        }

        /// Establishes connection with the transport
        ///
        /// This initiates the NWConnection and waits for it to become ready.
        /// Once the connection is established, it starts the message receiving loop.
        ///
        /// - Throws: Error if the connection fails to establish
        /// Dials again unless the transport is shutting down.
        ///
        /// The check and the redial happen in the same actor step. Sampling `isStopping` before
        /// a backoff sleep and acting on it afterwards asks whether the transport *was* running,
        /// which is a different question from whether it still is.
        ///
        /// - Throws: Whatever ``redial()`` throws.
        private func redialIfRunning() async throws {
            guard !isStopping else { return }
            try await redial()
        }

        /// Tears down the current connection and dials again, without yielding in between.
        ///
        /// The two halves used to be separate statements in a deferred task. Between them the
        /// actor could run anything else — including another reconnect — and the cancel would
        /// then land on the connection that had just replaced the failed one.
        ///
        /// - Throws: Whatever ``connect()`` throws once the old connection is gone.
        private func redial() async throws {
            connection.cancel()
            try await connect()
        }

        /// Starts the `NWConnection`, waits for it to become ready, then begins the receive loop (and the
        /// heartbeat, if enabled).
        ///
        /// A failed attempt is retried after a backoff delay, up to ``ReconnectionConfiguration/maxAttempts``
        /// retries, when reconnection is enabled. Calling it while already connected does nothing.
        ///
        /// - Throws: The underlying connection error once retries are exhausted, or immediately when
        ///   reconnection is disabled or the transport is stopping.
        public func connect() async throws {
            guard !isConnected else { return }

            // Reset state for fresh connection
            isStopping = false
            reconnectAttempt = 0

            // Retry loop with exponential backoff
            while !isConnected && reconnectAttempt <= reconnectionConfig.maxAttempts {
                do {
                    try await attemptConnection()
                    return  // Success
                } catch {
                    guard !isStopping,
                          reconnectionConfig.enabled,
                          reconnectAttempt < reconnectionConfig.maxAttempts
                    else {
                        throw error
                    }

                    // Schedule retry with backoff
                    reconnectAttempt += 1
                    let delay = reconnectionConfig.backoffDelay(for: reconnectAttempt)
                    logger.debug(
                        "Attempting reconnection",
                        metadata: [
                            "attempt": "\(reconnectAttempt)",
                            "maxAttempts": "\(reconnectionConfig.maxAttempts)",
                        ])

                    try await backoffSleep(.seconds(delay))
                    connection.cancel()
                }
            }

            throw MCPError.internalError("Failed to connect after \(reconnectAttempt) attempts")
        }

        /// Attempts a single connection
        ///
        /// Creates a stream for connection state changes and waits for a terminal state.
        ///
        /// - Throws: Error if the connection fails
        private func attemptConnection() async throws {
            // Create stream for state changes with proper cleanup
            let stateStream = AsyncStream<NWConnection.State> { continuation in
                continuation.onTermination = { [weak self] _ in
                    self?.connection.stateUpdateHandler = nil
                }

                connection.stateUpdateHandler = { state in
                    continuation.yield(state)
                    switch state {
                    case .ready, .failed, .cancelled:
                        continuation.finish()
                    default:
                        break
                    }
                }
            }

            connection.start(queue: .main)

            // Process states until terminal state
            for await state in stateStream {
                switch state {
                case .ready:
                    await handleConnectionReady()
                    return  // Success - exits loop and stream

                case .failed(let error):
                    logger.error("Connection failed", metadata: ["error": "\(error)"])
                    throw error  // Exits loop and stream

                case .cancelled:
                    logger.warning("Connection cancelled")
                    throw MCPError.internalError("Connection cancelled")

                case .waiting(let error):
                    logger.debug("Connection waiting", metadata: ["error": "\(error)"])

                case .preparing:
                    logger.debug("Connection preparing...")

                case .setup:
                    logger.debug("Connection setup...")

                @unknown default:
                    logger.warning("Unknown connection state")
                }
            }
        }

        /// Handles when the connection reaches the ready state
        private func handleConnectionReady() async {
            isConnected = true
            reconnectAttempt = 0
            logger.debug("Network transport connected successfully")

            // Start the receive loop after connection is established
            Task { await self.receiveLoop() }

            // Start heartbeat task if enabled
            if heartbeatConfig.enabled {
                startHeartbeat()
            }
        }

        /// Starts a task to periodically send heartbeats to check connection health
        private func startHeartbeat() {
            // Cancel any existing heartbeat task
            heartbeatTask?.cancel()

            // `logger` and the two configuration values are `nonisolated let`s — immutable, and
            // not isolated state at all. Bound to locals here so the task bodies below say what
            // they use instead of reaching back through `self` for a value that cannot change,
            // and so a log line does not depend on the transport still being alive.
            let log = logger
            let heartbeat = heartbeatConfig

            // Start a new heartbeat task
            heartbeatTask = Task { [weak self] in
                guard let self = self else { return }

                // Initial delay before starting heartbeats
                try? await Task.sleep(for: .seconds(1))

                while !Task.isCancelled {
                    do {
                        // Check actor-isolated properties first
                        // Named apart from the properties they were read from: a local that
                        // shadows the property it snapshots reads, three lines later, as though
                        // it were still the live value.
                        let stopping = await self.isStopping
                        let connected = await self.isConnected

                        guard !stopping && connected else { break }

                        try await self.sendHeartbeat()
                        try await Task.sleep(for: .seconds(heartbeat.interval))
                    } catch {
                        // If heartbeat fails, log and retry after a shorter interval
                        log.warning("Heartbeat failed", metadata: ["error": "\(error)"])
                        try? await Task.sleep(for: .seconds(2))
                    }
                }
            }
        }

        /// Sends a heartbeat message to verify connection health
        private func sendHeartbeat() async throws {
            guard isConnected && !isStopping else { return }

            // Try to send the heartbeat (without the newline delimiter used for normal messages)
            try await withCheckedThrowingContinuation {
                [weak self] (continuation: CheckedContinuation<Void, Swift.Error>) in
                guard let self = self else {
                    continuation.resume(throwing: MCPError.internalError("Transport deallocated"))
                    return
                }

                connection.send(
                    content: Heartbeat().data,
                    contentContext: .defaultMessage,
                    isComplete: true,
                    completion: .contentProcessed { [weak self] error in
                        if let error = error {
                            continuation.resume(throwing: error)
                        } else {
                            Task { [weak self] in
                                await self?.setLastHeartbeatTime(Date())
                            }
                            continuation.resume()
                        }
                    })
            }

            logger.trace("Heartbeat sent")
        }


        /// Stops the heartbeat, cancels the `NWConnection` and finishes the stream returned by ``receive()``.
        ///
        /// Marks the transport as stopping first so that no reconnection is attempted. Calling it while not
        /// connected does nothing.
        public func disconnect() async {
            guard isConnected else { return }

            // Mark as stopping to prevent reconnection attempts during disconnect
            isStopping = true
            isConnected = false

            // Cancel heartbeat task if it exists
            heartbeatTask?.cancel()
            heartbeatTask = nil

            connection.cancel()
            messageContinuation.finish()
            logger.debug("Network transport disconnected")
        }

        /// Sends one message over the connection, followed by a newline delimiter.
        ///
        /// If the send fails with a lost connection and reconnection is enabled, a reconnect is scheduled in the
        /// background after a 500 ms pause; the failed send itself is still reported to the caller.
        ///
        /// - Parameter message: The encoded JSON-RPC message, without a trailing newline.
        /// - Throws: `MCPError.internalError` if the transport is not connected, has been deallocated, or the
        ///   connection reports a send error.
        public func send(_ message: Data) async throws {
            guard isConnected else {
                throw MCPError.internalError("Transport not connected")
            }

            // Add newline as delimiter
            var messageWithNewline = message
            messageWithNewline.append(UInt8(ascii: "\n"))

            // Use a main-isolated variable to track continuation state
            let sendContinuationResumed = MainFlag()

            try await withCheckedThrowingContinuation {
                [weak self] (continuation: CheckedContinuation<Void, Swift.Error>) in
                guard let self = self else {
                    continuation.resume(throwing: MCPError.internalError("Transport deallocated"))
                    return
                }

                // Immutable, not isolated state: bound here so the completion chain below says
                // what it uses rather than reaching back through `self` for values that cannot
                // change while it runs.
                let log = self.logger
                let reconnection = self.reconnectionConfig

                connection.send(
                    content: messageWithNewline,
                    contentContext: .defaultMessage,
                    isComplete: true,
                    completion: .contentProcessed { [weak self] error in
                        guard let self = self else { return }

                        Task { @MainActor in
                            if !sendContinuationResumed.flag {
                                sendContinuationResumed.flag = true
                                if let error = error {
                                    log.error("Send error", metadata: ["error": "\(error)"])

                                    // Check if we should attempt to reconnect on send failure
                                    let stopping = await self.isStopping
                                    if !stopping && reconnection.enabled {
                                        let connected = await self.isConnected
                                        if connected {
                                            if error.isConnectionLost {
                                                log.warning(
                                                    "Connection appears broken, will attempt to reconnect..."
                                                )

                                                // Schedule connection restart.
                                                // Captures `self` strongly and deliberately: the
                                                // enclosing `Task` already holds it strongly via the
                                                // `guard let self` above, so a nested `[weak self]`
                                                // bought nothing and made the outer implicit capture
                                                // inconsistent with it — the ImplicitStrongCapture
                                                // warning. The reconnect must keep the transport
                                                // alive while it sleeps and redials; the retain ends
                                                // when this task does, and the completion closure
                                                // that owns the chain is released once it fires.
                                                Task { [self] in  // Operate on self's executor
                                                    await self.setIsConnected(false)

                                                    do {
                                                        try await Task.sleep(for: .milliseconds(500))

                                                        // One step on the actor rather than two.
                                                        // Cancelling and redialling separately leaves
                                                        // a window in which another path can replace
                                                        // `connection` between them — and then the
                                                        // cancel lands on the connection that just
                                                        // took its place.
                                                        try await self.redial()
                                                    } catch {
                                                        log.error(
                                                            "Reconnect after send failure failed",
                                                            metadata: ["error": "\(error)"])
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    continuation.resume(
                                        throwing: MCPError.internalError("Send error: \(error)"))
                                } else {
                                    continuation.resume()
                                }
                            }
                        }
                    })
            }
        }

        /// Returns the stream of inbound messages.
        ///
        /// Heartbeat packets are consumed internally and not yielded. Every call returns the same stream, so it
        /// should have a single reader. The stream finishes on ``disconnect()``.
        ///
        /// - Returns: A stream yielding one `Data` per newline-delimited message.
        public func receive() -> AsyncThrowingStream<Data, Swift.Error> {
            return messageStream
        }

        /// Continuous loop to receive and process incoming messages
        ///
        /// This method runs continuously while the connection is active,
        /// receiving data and yielding complete messages to the message stream.
        /// Messages are delimited by newline characters.
        private func receiveLoop() async {
            var buffer = Data()
            var consecutiveEmptyReads = 0
            let maxConsecutiveEmptyReads = 5

            while isConnected && !Task.isCancelled && !isStopping {
                do {
                    let newData = try await receiveData()

                    // Check for EOF or empty data
                    if newData.isEmpty {
                        consecutiveEmptyReads += 1

                        if consecutiveEmptyReads >= maxConsecutiveEmptyReads {
                            logger.warning(
                                "Multiple consecutive empty reads, possible connection issue",
                                metadata: ["consecutiveEmptyReads": "\(consecutiveEmptyReads)"])

                            // Check connection state
                            if connection.state != .ready {
                                logger.warning("Connection no longer ready, exiting receive loop")
                                break
                            }
                        }

                        // Brief pause before retry
                        try await Task.sleep(for: .milliseconds(100))
                        continue
                    }

                    // Check if this is a heartbeat message
                    if Heartbeat.isHeartbeat(newData) {
                        logger.trace("Received heartbeat from peer")

                        // Extract timestamp if available
                        if let heartbeat = Heartbeat.from(data: newData) {
                            logger.trace("Heartbeat timestamp: \(heartbeat.timestamp)")
                        }

                        // Reset the counter since we got valid data
                        consecutiveEmptyReads = 0
                        continue  // Skip regular message processing for heartbeats
                    }

                    // Reset counter on successful data read
                    consecutiveEmptyReads = 0
                    buffer.append(newData)

                    // Process complete messages
                    while let newlineIndex = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                        let messageData = buffer[..<newlineIndex]
                        buffer = buffer[(newlineIndex + 1)...]

                        if !messageData.isEmpty {
                            logger.debug(
                                "Message received", metadata: ["size": "\(messageData.count)"])
                            messageContinuation.yield(Data(messageData))
                        }
                    }
                } catch let error as NWError {
                    if !Task.isCancelled && !isStopping {
                        logger.error("Network error occurred", metadata: ["error": "\(error)"])

                        // Check for specific connection-related errors
                        if error.isConnectionLost {
                            // If we should reconnect, don't finish the message stream yet
                            if reconnectionConfig.enabled
                                && reconnectAttempt < reconnectionConfig.maxAttempts
                            {
                                reconnectAttempt += 1
                                logger.warning(
                                    "Network connection lost, attempting reconnection",
                                    metadata: [
                                        "attempt": "\(reconnectAttempt)",
                                        "maxAttempts": "\(reconnectionConfig.maxAttempts)",
                                    ])

                                // Mark as not connected while attempting reconnection
                                isConnected = false

                                // Schedule reconnection attempt
                                // The delay is computed here, on the actor, rather than inside
                                // the task: `reconnectAttempt` is what it is now, and reading it
                                // after a sleep would back off by whatever the count had become.
                                let delay = reconnectionConfig.backoffDelay(for: reconnectAttempt)
                                let log = logger
                                Task {
                                    do {
                                        try await backoffSleep(.seconds(delay))
                                        // `redial` is one step on the actor, and it re-reads
                                        // `isStopping` there rather than trusting a value sampled
                                        // before the sleep. If connect succeeds a new receive loop
                                        // starts with it.
                                        try await self.redialIfRunning()
                                    } catch {
                                        log.error(
                                            "Reconnect after connection loss failed",
                                            metadata: ["error": "\(error)"])
                                    }
                                }

                                // Exit this receive loop since we're starting a new one after reconnect
                                break
                            } else {
                                // We're not reconnecting, finish the message stream with error
                                messageContinuation.finish(
                                    throwing: MCPError.transportError(error))
                                break
                            }
                        } else {
                            // For other network errors, log but continue trying
                            do {
                                try await Task.sleep(for: .milliseconds(100))  // 100ms pause
                                continue
                            } catch {
                                logger.error("Failed to sleep after network error", metadata: ["error": "\(error)"])
                                break
                            }
                        }
                    }
                    break
                } catch {
                    if !Task.isCancelled && !isStopping {
                        logger.error("Receive error", metadata: ["error": "\(error)"])

                        if reconnectionConfig.enabled
                            && reconnectAttempt < reconnectionConfig.maxAttempts
                        {
                            // Similar reconnection logic for other errors
                            reconnectAttempt += 1
                            logger.warning(
                                "Error during receive, attempting reconnection",
                                metadata: [
                                    "attempt": "\(reconnectAttempt)",
                                    "maxAttempts": "\(reconnectionConfig.maxAttempts)",
                                ])

                            isConnected = false

                            let delay = reconnectionConfig.backoffDelay(for: reconnectAttempt)
                            let log = logger
                            Task {
                                do {
                                    try await backoffSleep(.seconds(delay))
                                    try await self.redialIfRunning()
                                } catch {
                                    log.error(
                                        "Reconnect after receive error failed",
                                        metadata: ["error": "\(error)"])
                                }
                            }

                            break
                        } else {
                            messageContinuation.finish(throwing: error)
                        }
                    }
                    break
                }
            }

            // If stopping normally, finish the stream without error
            if isStopping {
                logger.debug("Receive loop stopping normally")
                messageContinuation.finish()
            }
        }

        /// Receives a chunk of data from the network connection
        ///
        /// - Returns: The received data chunk
        /// - Throws: Network errors or transport failures
        private func receiveData() async throws -> Data {
            // Use a main-isolated variable to track continuation state
            let receiveContinuationResumed = MainFlag()

            return try await withCheckedThrowingContinuation {
                [weak self] (continuation: CheckedContinuation<Data, Swift.Error>) in
                guard let self = self else {
                    continuation.resume(throwing: MCPError.internalError("Transport deallocated"))
                    return
                }

                let maxLength = bufferConfig.maxReceiveBufferSize ?? Int.max
                // Immutable and not isolated state, bound here so the completion below does not
                // reach back through `self` for it.
                let log = self.logger
                connection.receive(minimumIncompleteLength: 1, maximumLength: maxLength) {
                    content, _, isComplete, error in
                    Task { @MainActor in
                        if !receiveContinuationResumed.flag {
                            receiveContinuationResumed.flag = true
                            if let error = error {
                                continuation.resume(throwing: MCPError.transportError(error))
                            } else if let content = content {
                                continuation.resume(returning: content)
                            } else if isComplete {
                                log.trace("Connection completed by peer")
                                continuation.resume(throwing: MCPError.connectionClosed)
                            } else {
                                // EOF: Resume with empty data instead of throwing an error
                                continuation.resume(returning: Data())
                            }
                        }
                    }
                }
            }
        }

        private func setLastHeartbeatTime(_ time: Date) {
            self.lastHeartbeatTime = time
        }

        private func setIsConnected(_ connected: Bool) {
            self.isConnected = connected
        }
    }
    @MainActor final class MainFlag { var flag = false }

    extension NWError {
        /// Whether this error indicates a connection has been lost or reset.
        fileprivate var isConnectionLost: Bool {
            let nsError = self as NSError
            return nsError.code == 57  // Socket is not connected (EHOSTUNREACH or ENOTCONN)
                || nsError.code == 54  // Connection reset by peer (ECONNRESET)
        }
    }
#endif
