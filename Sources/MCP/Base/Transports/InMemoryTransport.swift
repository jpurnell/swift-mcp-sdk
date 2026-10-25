import Foundation
import Logging

/// A ``Transport`` that connects a client and a server inside one process by handing message data directly
/// from one transport actor to its paired peer, with no framing, encoding or I/O.
///
/// Obtain a linked pair from ``createConnectedPair(logger:)``; a lone transport cannot connect. Useful for
/// tests and for embedding a server alongside its client.
///
/// - Example:
///   ```swift
///   // Create a connected pair of transports
///   let (clientTransport, serverTransport) = await InMemoryTransport.createConnectedPair()
///
///   // Use with client and server
///   let client = Client(name: "MyApp", version: "1.0.0")
///   let server = Server(name: "MyServer", version: "1.0.0")
///
///   try await client.connect(transport: clientTransport)
///   try await server.start(transport: serverTransport)
///   ```
public actor InMemoryTransport: Transport {
    /// The logger that receives this transport's diagnostics. A no-op logger is used if none was supplied.
    public nonisolated let logger: Logger

    private var isConnected = false
    private var pairedTransport: InMemoryTransport?

    // Message queues
    private var incomingMessages: [Data] = []
    private var messageContinuation: AsyncThrowingStream<Data, Swift.Error>.Continuation?

    /// Creates an unpaired in-memory transport.
    ///
    /// It cannot ``connect()`` until it is paired; prefer ``createConnectedPair(logger:)``.
    ///
    /// - Parameter logger: Logger for transport diagnostics. Defaults to `nil`, which discards log output.
    public init(logger: Logger? = nil) {
        self.logger =
            logger
            ?? Logger(
                label: "mcp.transport.in-memory",
                factory: { _ in SwiftLogNoOpLogHandler() }
            )
    }

    /// Creates a connected pair of in-memory transports
    ///
    /// This is the recommended way to create transports for client-server communication
    /// within the same process. The returned transports are already paired and ready
    /// to be connected.
    ///
    /// - Parameter logger: Logger shared by both transports. Defaults to `nil`, in which case each gets its own
    ///   no-op logger labelled for the client or server side.
    /// - Returns: The client-side and server-side transports, paired with each other. Each still needs
    ///   ``connect()`` to be called.
    public static func createConnectedPair(
        logger: Logger? = nil
    ) async -> (client: InMemoryTransport, server: InMemoryTransport) {
        let clientLogger: Logger
        let serverLogger: Logger

        if let providedLogger = logger {
            // If a logger is provided, use it directly for both transports
            clientLogger = providedLogger
            serverLogger = providedLogger
        } else {
            // Create default loggers with appropriate labels
            clientLogger = Logger(
                label: "mcp.transport.in-memory.client",
                factory: { _ in SwiftLogNoOpLogHandler() }
            )
            serverLogger = Logger(
                label: "mcp.transport.in-memory.server",
                factory: { _ in SwiftLogNoOpLogHandler() }
            )
        }

        let clientTransport = InMemoryTransport(logger: clientLogger)
        let serverTransport = InMemoryTransport(logger: serverLogger)

        // Perform pairing
        await clientTransport.pair(with: serverTransport)
        await serverTransport.pair(with: clientTransport)

        return (clientTransport, serverTransport)
    }

    /// Pairs this transport with another for bidirectional communication
    ///
    /// - Parameter other: The transport to pair with
    /// - Important: This method should typically not be called directly.
    ///   Use `createConnectedPair()` instead.
    private func pair(with other: InMemoryTransport) {
        self.pairedTransport = other
    }

    /// Marks the transport connected after checking that it has a paired peer.
    ///
    /// Calling it while already connected logs and returns.
    ///
    /// - Throws: `MCPError.internalError` if the transport was not created through
    ///   ``createConnectedPair(logger:)``.
    public func connect() async throws {
        guard !isConnected else {
            logger.debug("Transport already connected")
            return
        }

        guard pairedTransport != nil else {
            throw MCPError.internalError(
                "Transport not paired. Use createConnectedPair() to create paired transports.")
        }

        isConnected = true
        logger.info("Transport connected successfully")
    }

    /// Marks the transport disconnected and finishes its receive stream.
    ///
    /// The paired peer is told, and its receive stream then finishes with `MCPError.connectionClosed`. Calling
    /// it while not connected does nothing.
    public func disconnect() async {
        guard isConnected else { return }

        isConnected = false
        messageContinuation?.finish()
        messageContinuation = nil

        // Notify paired transport of disconnection
        if let paired = pairedTransport {
            await paired.handlePeerDisconnection()
        }

        logger.info("Transport disconnected")
    }

    /// Handles disconnection from the paired transport
    private func handlePeerDisconnection() {
        if isConnected {
            messageContinuation?.finish(throwing: MCPError.connectionClosed)
            messageContinuation = nil
            isConnected = false
            logger.info("Peer transport disconnected")
        }
    }

    /// Sends a message to the paired transport
    ///
    /// Messages are delivered directly to the paired transport's receive queue
    /// without any additional encoding or framing.
    ///
    /// If the peer has not yet called ``receive()``, the message is queued and delivered when it does. If the
    /// peer is disconnected, the message is dropped with a warning.
    ///
    /// - Parameter data: The complete encoded message to deliver.
    /// - Throws: `MCPError.internalError` if this transport is not connected or has no paired peer.
    public func send(_ data: Data) async throws {
        guard isConnected else {
            throw MCPError.internalError("Transport not connected")
        }

        guard let paired = pairedTransport else {
            throw MCPError.internalError("No paired transport")
        }

        logger.debug("Sending message", metadata: ["size": "\(data.count)"])

        // Deliver message to paired transport
        await paired.deliverMessage(data)
    }

    /// Delivers a message from the paired transport
    private func deliverMessage(_ data: Data) {
        guard isConnected else {
            logger.warning("Received message while disconnected")
            return
        }

        logger.debug("Message received", metadata: ["size": "\(data.count)"])

        if let continuation = messageContinuation {
            continuation.yield(data)
        } else {
            // Queue message if stream not yet created
            incomingMessages.append(data)
        }
    }

    /// Returns the stream of messages sent by the paired transport.
    ///
    /// Messages queued before this call are yielded first. Only one stream is live at a time: a later call
    /// replaces the continuation of an earlier one. The stream finishes on ``disconnect()`` and fails with
    /// `MCPError.connectionClosed` if the peer disconnects first.
    ///
    /// - Returns: A stream yielding one `Data` per message, in send order.
    public func receive() -> AsyncThrowingStream<Data, Swift.Error> {
        return AsyncThrowingStream<Data, Swift.Error> { continuation in
            self.messageContinuation = continuation

            // Deliver any queued messages
            for message in self.incomingMessages {
                continuation.yield(message)
            }
            self.incomingMessages.removeAll()

            // Check if already disconnected
            if !self.isConnected {
                continuation.finish()
            }
        }
    }
}
