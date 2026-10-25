import Foundation

/// The Model Context Protocol (MCP) provides a standardized way for servers to send
/// structured log messages to clients. Clients can control logging verbosity by setting
/// minimum log levels, with servers sending notifications containing severity levels,
/// optional logger names, and arbitrary JSON-serializable data.
///
/// - SeeAlso: https://modelcontextprotocol.io/specification/2025-11-25/server/utilities/logging/
public enum LogLevel: String, Hashable, Codable, Sendable, CaseIterable {
    /// Detailed debugging information
    case debug
    /// General informational messages
    case info
    /// Normal but significant events
    case notice
    /// Warning conditions
    case warning
    /// Error conditions
    case error
    /// Critical conditions
    case critical
    /// Action must be taken immediately
    case alert
    /// System is unusable
    case emergency
}

// MARK: - Set Log Level

/// To configure the minimum log level, clients MAY send a `logging/setLevel` request.
/// - SeeAlso: https://modelcontextprotocol.io/specification/2025-11-25/server/utilities/logging/
/// - Warning: `logging/setLevel` is REMOVED by MCP `2026-07-28`; the log level for a single
///   request travels in `_meta` as ``Metadata/logLevel``. The Logging feature as a whole is
///   deprecated — log to stderr or use OpenTelemetry. See ``Deprecations``.
public enum SetLoggingLevel: Method {
    /// The JSON-RPC method name, `logging/setLevel`.
    public static let name = "logging/setLevel"

    /// Parameters for the `logging/setLevel` request.
    public struct Parameters: Hashable, Codable, Sendable {
        /// The minimum log level to set
        public let level: LogLevel

        /// Creates parameters for a `logging/setLevel` request.
        ///
        /// - Parameter level: The minimum severity the server should send; lower-severity messages are
        ///   expected to be suppressed.
        public init(level: LogLevel) {
            self.level = level
        }
    }

    /// The `logging/setLevel` request returns an empty result on success.
    public typealias Result = Empty
}

// MARK: - Log Message Notification

/// Servers send log messages using `notifications/message` notifications.
/// - SeeAlso: https://modelcontextprotocol.io/specification/2025-11-25/server/utilities/logging/
public struct LogMessageNotification: Notification {
    /// The JSON-RPC notification name, `notifications/message`.
    public static let name = "notifications/message"

    /// Parameters for the `notifications/message` notification.
    public struct Parameters: Hashable, Codable, Sendable {
        /// The severity level of the log message
        public let level: LogLevel
        /// Optional logger name to identify the source
        public let logger: String?
        /// Arbitrary JSON-serializable data for the log message
        public let data: Value

        /// Creates the parameters for a `notifications/message` log notification.
        ///
        /// - Parameters:
        ///   - level: The severity of the message.
        ///   - logger: Optional name of the logger or component that produced it; `nil` for none.
        ///   - data: The message payload, any JSON-serializable ``Value``.
        public init(
            level: LogLevel,
            logger: String? = nil,
            data: Value
        ) {
            self.level = level
            self.logger = logger
            self.data = data
        }
    }
}
