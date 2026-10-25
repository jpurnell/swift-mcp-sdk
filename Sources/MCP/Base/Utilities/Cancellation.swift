import Foundation

/// The Model Context Protocol supports cancellation of requests through
/// notification messages. Either side can send a cancellation notification
/// to indicate that a previously-issued request should be cancelled.
///
/// Cancellation is advisory: the receiver should make a best-effort attempt
/// to cancel the operation, but may not always be able to do so.
///
/// - SeeAlso: https://modelcontextprotocol.io/specification/2025-11-25/basic/utilities/cancellation
public struct CancelledNotification: Notification {
    /// The JSON-RPC method name for this notification: `notifications/cancelled`.
    public static let name: String = "notifications/cancelled"

    /// Parameters for the `CancelledNotification` notification.
    public struct Parameters: Hashable, Codable, Sendable {
        /// The ID of the request to cancel.
        ///
        /// This MUST correspond to the ID of a request previously issued
        /// in the same direction. Optional per the spec (`requestId?`).
        public let requestId: ID?

        /// An optional human-readable reason for the cancellation.
        public let reason: String?

        /// Creates the parameters for a `notifications/cancelled` notification.
        ///
        /// - Parameters:
        ///   - requestId: The ID of the in-flight request to cancel, as originally sent. Defaults to `nil`
        ///     (the field is optional in the spec); omitted from the wire when `nil`.
        ///   - reason: Optional human-readable explanation, intended for logging. Defaults to `nil`.
        public init(requestId: ID? = nil, reason: String? = nil) {
            self.requestId = requestId
            self.reason = reason
        }
    }
}
