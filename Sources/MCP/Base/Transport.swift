import Logging

import struct Foundation.Data

/// The byte-level channel over which an MCP client or server exchanges JSON-RPC messages.
///
/// A transport moves opaque, already-encoded message payloads; it does not interpret them. Conforming
/// types are actors so connection state is isolated. The usual lifecycle is ``connect()``, then any
/// number of ``send(_:)`` calls while a consumer iterates ``receive()``, then ``disconnect()``.
public protocol Transport: Actor {
    /// The logger the transport reports connection and I/O diagnostics to.
    var logger: Logger { get }

    /// Opens the underlying channel so that messages can be sent and received.
    ///
    /// Call once before ``send(_:)`` or ``receive()``. Implementations define whether calling it a
    /// second time is a no-op or an error.
    ///
    /// - Throws: A transport-specific error if the channel cannot be established.
    func connect() async throws

    /// Closes the underlying channel and releases its resources.
    ///
    /// Streams returned by ``receive()`` finish once the transport is disconnected. Does not throw;
    /// failures while closing are the implementation's to log.
    func disconnect() async

    /// Transmits one encoded message to the peer.
    ///
    /// - Parameter data: A complete, JSON-encoded JSON-RPC message. Framing (newline delimiting,
    ///   HTTP bodies and so on) is applied by the transport.
    /// - Throws: A transport-specific error if the transport is not connected or the write fails.
    func send(_ data: Data) async throws

    /// Returns the stream of messages arriving from the peer.
    ///
    /// - Returns: A stream yielding one `Data` per complete inbound message, in arrival order. The
    ///   stream finishes when the transport disconnects and throws if the channel fails.
    func receive() -> AsyncThrowingStream<Data, Swift.Error>
}
