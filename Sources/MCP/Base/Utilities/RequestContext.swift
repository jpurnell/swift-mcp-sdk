import Foundation

/// A context object that wraps a pending request, providing both the request ID
/// and a Task handle for the asynchronous operation.
///
/// This allows you to track and cancel in-flight requests by sending
/// a CancelledNotification to the receiver (client or server).
///
/// - SeeAlso: https://modelcontextprotocol.io/specification/2025-11-25/basic/utilities/cancellation
public struct RequestContext<Output: Sendable & Decodable>: Sendable {
    /// The unique identifier for this request.
    public let requestID: ID

    /// The Task representing the asynchronous work for this request.
    private let requestTask: Task<Output, Error>

    /// Convenience property to await the result.
    ///
    /// Example:
    /// ```swift
    /// func pingResult(client: Client) async throws {
    ///     let context = try await client.send(Ping.request())
    ///     let result = try await context.value
    ///     print("Ping returned: \(result)")
    /// }
    /// ```
    public var value: Output {
        get async throws {
            try await requestTask.value
        }
    }

    /// Wraps an in-flight request so callers can await its result and know its ID for cancellation.
    ///
    /// Normally created by the client or server when it sends a request, not by application code.
    ///
    /// - Parameters:
    ///   - requestID: The JSON-RPC ID the request was sent with; use it as the `requestId` of a
    ///     `CancelledNotification`.
    ///   - requestTask: The task that completes with the decoded response, or throws if the request
    ///     fails.
    public init(requestID: ID, requestTask: Task<Output, Error>) {
        self.requestID = requestID
        self.requestTask = requestTask
    }
}
