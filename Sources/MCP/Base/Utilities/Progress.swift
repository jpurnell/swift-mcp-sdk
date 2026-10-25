import Foundation

/// Progress notifications are used to report progress on long-running operations.
///
/// The sender (either client or server) that issued the original request may
/// include a progress token in the request's `_meta` field. If the receiver
/// supports progress reporting, it can send progress notifications
/// containing that token to indicate how the operation is proceeding.
///
/// - SeeAlso: https://modelcontextprotocol.io/specification/2025-11-25/basic/utilities/progress
public struct ProgressNotification: Notification {
    /// The JSON-RPC method name for this notification: `notifications/progress`.
    public static let name: String = "notifications/progress"

    /// Parameters for the `ProgressNotification` notification.
    public struct Parameters: Hashable, Codable, Sendable {
        /// The progress token from the original request.
        ///
        /// This is used to associate the progress notification with its
        /// originating request.
        public let progressToken: ProgressToken

        /// The current progress value.
        ///
        /// This should increase monotonically as the operation proceeds.
        /// It represents the amount of work completed so far.
        public let progress: Double

        /// The total expected progress value, if known.
        ///
        /// When provided, `progress / total` can be used to calculate
        /// a percentage completion.
        public let total: Double?

        /// An optional human-readable message describing the current progress.
        public let message: String?

        /// Creates the parameters for a `notifications/progress` notification.
        ///
        /// - Parameters:
        ///   - progressToken: The `_meta.progressToken` taken from the request being reported on.
        ///   - progress: Work completed so far; it should increase with each notification. Units are
        ///     defined by the sender and may be fractional.
        ///   - total: Total work expected in the same units as `progress`. Defaults to `nil` (unknown) and
        ///     is omitted from the wire when `nil`.
        ///   - message: Optional human-readable status text. Defaults to `nil`.
        public init(
            progressToken: ProgressToken,
            progress: Double,
            total: Double? = nil,
            message: String? = nil
        ) {
            self.progressToken = progressToken
            self.progress = progress
            self.total = total
            self.message = message
        }
    }
}

/// A token used to associate progress notifications with their originating request.
///
/// Progress tokens can be either strings or integers.
/// Progress tokens MUST be unique across all active requests.
public enum ProgressToken: Hashable, Codable, Sendable {
    /// A string token, encoded as a JSON string.
    case string(String)
    /// An integer token, encoded as a JSON number.
    case integer(Int)

    /// Decodes a token from a single JSON value.
    ///
    /// A JSON string becomes `.string`; otherwise a JSON integer becomes `.integer`.
    ///
    /// - Parameter decoder: The decoder to read the value from.
    /// - Throws: `DecodingError.dataCorrupted` if the value is neither a string nor an integer (for example a
    ///   boolean, object, or fractional number).
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
        } else if let intValue = try? container.decode(Int.self) {
            self = .integer(intValue)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Progress token must be a string or integer"
            )
        }
    }

    /// Encodes the token as a bare JSON string or integer, matching the `progressToken` wire shape.
    ///
    /// - Parameter encoder: The encoder to write the value to.
    /// - Throws: An error if the underlying encoder fails.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .integer(let value):
            try container.encode(value)
        }
    }

    /// Creates a new string token from a random UUID, suitable for tagging one outgoing request.
    public static func unique() -> ProgressToken {
        .string(UUID().uuidString)
    }
}

/// Metadata that can be included in request parameters.
///
/// This structure represents the `_meta` field in MCP request parameters,
/// which can contain a progress token for receiving progress notifications.
///
/// - SeeAlso: https://modelcontextprotocol.io/specification/2025-11-25/basic/utilities/progress
public struct Metadata: Hashable, Codable, Sendable {
    /// Returns the value stored under `key` in `fields`, or `nil` if the key is absent.
    public subscript(_ key: String) -> Value? {
        fields[key]
    }

    /// The underlying fields dictionary.
    public var fields: [String: Value]

    /// The progress token for receiving progress notifications.
    ///
    /// If specified, the caller is requesting out-of-band progress notifications
    /// for this request. The value of this parameter is an opaque token that will
    /// be attached to any subsequent notifications. The receiver is not obligated
    /// to provide these notifications.
    public var progressToken: ProgressToken? {
        get {
            guard let value = fields["progressToken"] else { return nil }
            if let stringValue = value.stringValue {
                return .string(stringValue)
            } else if let intValue = value.intValue {
                return .integer(intValue)
            }
            return nil
        }
        set {
            if let token = newValue {
                switch token {
                case .string(let s):
                    fields["progressToken"] = .string(s)
                case .integer(let i):
                    fields["progressToken"] = .int(i)
                }
            } else {
                fields.removeValue(forKey: "progressToken")
            }
        }
    }

    /// Creates the `_meta` object for a request's parameters.
    ///
    /// - Parameters:
    ///   - progressToken: If non-nil, stored under `progressToken` to ask the receiver for progress
    ///     notifications. Defaults to `nil`. A non-nil token overwrites any `progressToken` key in
    ///     `additionalFields`.
    ///   - additionalFields: Other `_meta` entries, copied as given. Defaults to empty.
    public init(progressToken: ProgressToken? = nil, additionalFields: [String: Value] = [:]) {
        self.fields = additionalFields
        self.progressToken = progressToken
    }

    /// Decodes metadata from a single JSON object.
    ///
    /// Every key is kept verbatim in `fields`, including `progressToken` and any vendor-specific keys.
    ///
    /// - Parameter decoder: The decoder to read the value from.
    /// - Throws: `DecodingError` if the value is not a JSON object whose values are all valid `Value`s.
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.fields = try container.decode([String: Value].self)
    }

    /// Encodes the metadata as a JSON object containing exactly the entries of `fields`.
    ///
    /// - Parameter encoder: The encoder to write the value to.
    /// - Throws: An error if the underlying encoder fails.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(fields)
    }
}
