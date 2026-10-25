import Logging

import struct Foundation.Data

#if canImport(System)
    import System
#else
    @preconcurrency import SystemPackage
#endif

// Import for specific low-level operations not yet in Swift System
#if canImport(Darwin)
    import Darwin.POSIX
#elseif canImport(Glibc)
    import Glibc
#elseif canImport(Musl)
    import Musl
#endif

#if canImport(Darwin) || canImport(Glibc) || canImport(Musl)
    /// An implementation of the MCP stdio transport protocol.
    ///
    /// This transport implements the [stdio transport](https://modelcontextprotocol.io/specification/2025-06-18/basic/transports#stdio)
    /// specification from the Model Context Protocol.
    ///
    /// The stdio transport works by:
    /// - Reading JSON-RPC messages from standard input
    /// - Writing JSON-RPC messages to standard output
    /// - Using newline characters as message delimiters
    /// - Supporting non-blocking I/O operations
    ///
    /// This transport is the recommended option for most MCP applications due to its
    /// simplicity and broad platform support.
    ///
    /// - Important: This transport is available on Apple platforms and Linux distributions with glibc
    ///   (Ubuntu, Debian, Fedora, CentOS, RHEL).
    ///
    /// ## Example Usage
    ///
    /// ```swift
    /// import MCP
    ///
    /// // Initialize the client
    /// let client = Client(name: "MyApp", version: "1.0.0")
    ///
    /// // Create a transport and connect
    /// let transport = StdioTransport()
    /// try await client.connect(transport: transport)
    /// ```
    public actor StdioTransport: Transport {
        private let input: FileDescriptor
        private let output: FileDescriptor
        /// The logger that receives this transport's diagnostics. A no-op logger is used if none was supplied.
        public nonisolated let logger: Logger

        private var isConnected = false
        private let messageStream: AsyncThrowingStream<Data, Swift.Error>
        private let messageContinuation: AsyncThrowingStream<Data, Swift.Error>.Continuation

        /// Creates a stdio transport that reads newline-delimited messages from one file descriptor and writes
        /// them to another.
        ///
        /// The descriptors are not touched until ``connect()`` switches them to non-blocking mode. The transport
        /// does not close them.
        ///
        /// - Parameters:
        ///   - input: Descriptor to read inbound messages from. Defaults to standard input.
        ///   - output: Descriptor to write outbound messages to. Defaults to standard output.
        ///   - logger: Logger for transport diagnostics. Defaults to `nil`, which discards log output.
        public init(
            input: FileDescriptor = FileDescriptor.standardInput,
            output: FileDescriptor = FileDescriptor.standardOutput,
            logger: Logger? = nil
        ) {
            self.input = input
            self.output = output
            self.logger =
                logger
                ?? Logger(
                    label: "mcp.transport.stdio",
                    factory: { _ in SwiftLogNoOpLogHandler() })

            // Create message stream
            var continuation: AsyncThrowingStream<Data, Swift.Error>.Continuation!
            self.messageStream = AsyncThrowingStream { continuation = $0 }
            self.messageContinuation = continuation
        }

        /// Switches both file descriptors to non-blocking mode and starts the background loop that reads
        /// messages into the stream returned by ``receive()``.
        ///
        /// Calling it while already connected does nothing.
        ///
        /// - Throws: `MCPError.transportError` wrapping the `Errno` if `fcntl` fails on either descriptor.
        public func connect() async throws {
            guard !isConnected else { return }

            // Set non-blocking mode
            try setNonBlocking(fileDescriptor: input)
            try setNonBlocking(fileDescriptor: output)

            isConnected = true
            logger.debug("Transport connected successfully")

            // Start reading loop in background
            Task {
                await readLoop()
            }
        }

        /// Configures a file descriptor for non-blocking I/O
        ///
        /// - Parameter fileDescriptor: The file descriptor to configure
        /// - Throws: Error if the operation fails
        private func setNonBlocking(fileDescriptor: FileDescriptor) throws {
            #if canImport(Darwin) || canImport(Glibc) || canImport(Musl)
                // Get current flags
                let flags = fcntl(fileDescriptor.rawValue, F_GETFL)
                guard flags >= 0 else {
                    throw MCPError.transportError(Errno(rawValue: CInt(errno)))
                }

                // Set non-blocking flag
                let result = fcntl(fileDescriptor.rawValue, F_SETFL, flags | O_NONBLOCK)
                guard result >= 0 else {
                    throw MCPError.transportError(Errno(rawValue: CInt(errno)))
                }
            #else
                // For platforms where non-blocking operations aren't supported
                throw MCPError.internalError(
                    "Setting non-blocking mode not supported on this platform")
            #endif
        }

        /// Continuous loop that reads and processes incoming messages
        ///
        /// This method runs in the background while the transport is connected,
        /// parsing complete messages delimited by newlines and yielding them
        /// to the message stream.
        private func readLoop() async {
            let bufferSize = 4096
            var buffer = [UInt8](repeating: 0, count: bufferSize)
            var pendingData = Data()

            while isConnected && !Task.isCancelled {
                do {
                    // `withUnsafeMutableBytes` hands over the raw buffer directly. Building
                    // an `UnsafeMutableRawBufferPointer` inside the block instead put a second
                    // pointer to the same memory in scope, which is the shape that goes wrong
                    // when someone later returns it.
                    let bytesRead = try buffer.withUnsafeMutableBytes { raw -> Int in
                        // Bound to a local and returned separately, so what leaves the block is
                        // plainly the count and not the buffer it was read into.
                        let count = try input.read(into: raw)
                        return count
                    }

                    if bytesRead == 0 {
                        logger.notice("EOF received")
                        break
                    }

                    pendingData.append(Data(buffer[..<bytesRead]))

                    // Process complete messages
                    while let newlineIndex = pendingData.firstIndex(of: UInt8(ascii: "\n")) {
                        let messageData = pendingData[..<newlineIndex]
                        pendingData = pendingData[(newlineIndex + 1)...]

                        if !messageData.isEmpty {
                            logger.trace(
                                "Message received", metadata: ["size": "\(messageData.count)"])
                            messageContinuation.yield(Data(messageData))
                        }
                    }
                } catch let error where MCPError.isResourceTemporarilyUnavailable(error) {
                    logger.debug("Input not ready; retrying read", metadata: ["error": "\(error)"])
                    try? await Task.sleep(for: .milliseconds(10))
                    continue
                } catch {
                    if !Task.isCancelled {
                        logger.error("Read error occurred", metadata: ["error": "\(error)"])
                    }
                    break
                }
            }

            messageContinuation.finish()
        }

        /// Marks the transport disconnected and finishes the stream returned by ``receive()``.
        ///
        /// The read loop exits at its next iteration. The file descriptors are left open. Calling it while not
        /// connected does nothing.
        public func disconnect() async {
            guard isConnected else { return }
            isConnected = false
            messageContinuation.finish()
            logger.debug("Transport disconnected")
        }

        /// Sends a message over the transport.
        ///
        /// This method supports sending both individual JSON-RPC messages and JSON-RPC batches.
        /// Batches should be encoded as a JSON array containing multiple request/notification objects
        /// according to the JSON-RPC 2.0 specification.
        ///
        /// A newline is appended as the delimiter, so the payload must not itself contain a newline. Writes that
        /// would block are retried every 10 ms until the whole message is written.
        ///
        /// - Parameter message: The encoded message, without a trailing newline.
        /// - Throws: `MCPError.transportError` wrapping `ENOTCONN` if the transport is not connected, or wrapping
        ///   the write error; `CancellationError` if the task is cancelled while waiting to retry.
        public func send(_ message: Data) async throws {
            guard isConnected else {
                throw MCPError.transportError(Errno(rawValue: ENOTCONN))
            }

            // Add newline as delimiter
            var messageWithNewline = message
            messageWithNewline.append(UInt8(ascii: "\n"))

            var remaining = messageWithNewline
            while !remaining.isEmpty {
                do {
                    // The block's own argument is already an `UnsafeRawBufferPointer`; the
                    // conversion only made a second pointer to the same bytes.
                    let written = try remaining.withUnsafeBytes { buffer -> Int in
                        let count = try output.write(buffer)
                        return count
                    }
                    if written > 0 {
                        remaining = remaining.dropFirst(written)
                    }
                } catch let error where MCPError.isResourceTemporarilyUnavailable(error) {
                    logger.debug("Output not ready; retrying write", metadata: ["error": "\(error)"])
                    try await Task.sleep(for: .milliseconds(10))
                    continue
                } catch {
                    throw MCPError.transportError(error)
                }
            }
        }

        /// Returns the stream of inbound messages.
        ///
        /// Each element is one non-empty line of input with the newline removed; it is not parsed here, so it is
        /// whatever the peer wrote (a request, notification, response or batch). The stream finishes on end of
        /// input, on a read error, or when ``disconnect()`` is called.
        ///
        /// - Returns: A stream yielding one `Data` per line, in arrival order.
        public func receive() -> AsyncThrowingStream<Data, Swift.Error> {
            return messageStream
        }
    }
#endif
