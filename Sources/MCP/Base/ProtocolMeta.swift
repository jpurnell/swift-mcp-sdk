import Foundation

/// Per-request protocol carriage, introduced by MCP `2026-07-28` (SEP-2575).
///
/// The `initialize` / `notifications/initialized` handshake is removed in that revision. A
/// request instead declares its own protocol version and client capabilities in `_meta`, so any
/// server instance can answer any request without sticky sessions or a shared session store.
///
/// ## Why these are accessors rather than new types
///
/// The specification describes `RequestMetaObject`, `ResultMetaObject` and
/// `NotificationMetaObject` as shapes over an **open** JSON object whose reserved keys are
/// namespaced strings. ``Metadata`` is already exactly that — a `[String: Value]` bag with typed
/// accessors over it, which is how `progressToken` is modelled. Adding three parallel Swift
/// types would fragment `_meta` at the type level for a distinction the wire format does not
/// make, and would force every call site to choose between them.
///
/// Reading an absent key yields `nil` rather than a default. That matters: a request from a
/// client on an earlier revision carries no version, and must stay distinguishable from a
/// `2026-07-28` request that failed to declare one.
extension Metadata {
    /// The reserved `_meta` keys defined by the specification.
    ///
    /// Namespaced under `io.modelcontextprotocol/`, which is reserved — callers must not write
    /// their own keys there.
    public enum Keys {
        /// The protocol version this request is written against.
        public static let protocolVersion = "io.modelcontextprotocol/protocolVersion"
        /// The capabilities of the client making the request.
        public static let clientCapabilities = "io.modelcontextprotocol/clientCapabilities"
        /// The identity of the client making the request.
        public static let clientInfo = "io.modelcontextprotocol/clientInfo"
        /// The identity of the server producing the result.
        public static let serverInfo = "io.modelcontextprotocol/serverInfo"
        /// The log level requested for this one request.
        public static let logLevel = "io.modelcontextprotocol/logLevel"
        /// The subscription a notification belongs to.
        public static let subscriptionId = "io.modelcontextprotocol/subscriptionId"
    }

    /// Round-trips a `Codable` value through ``Value`` so it can live in ``fields``.
    private func codableField<T: Codable>(_ key: String, as type: T.Type) -> T? {
        guard let value = fields[key] else { return nil }
        guard let data = try? JSONEncoder().encode(value) else { return nil } // silent: an unencodable field reads as absent rather than trapping
        return try? JSONDecoder().decode(T.self, from: data) // silent: a field of the wrong shape reads as absent, which is how an earlier revision looks
    }

    private mutating func setCodableField<T: Codable>(_ key: String, _ newValue: T?) {
        guard let newValue else {
            fields.removeValue(forKey: key)
            return
        }
        // silent: a value that cannot round-trip through `Value` is not written, leaving the
        // key absent rather than storing something the wire format cannot carry.
        guard let data = try? JSONEncoder().encode(newValue),
            let value = try? JSONDecoder().decode(Value.self, from: data)
        else { return }
        fields[key] = value
    }

    /// The protocol version this request is written against.
    ///
    /// Required on a request under `2026-07-28`. `nil` means the sender did not declare one —
    /// which is what a client on an earlier revision looks like.
    public var protocolVersion: String? {
        get { fields[Keys.protocolVersion]?.stringValue }
        set {
            if let newValue {
                fields[Keys.protocolVersion] = .string(newValue)
            } else {
                fields.removeValue(forKey: Keys.protocolVersion)
            }
        }
    }

    /// The capabilities of the client making this request.
    ///
    /// Required on a request under `2026-07-28`, since there is no handshake in which to have
    /// exchanged them.
    public var clientCapabilities: Client.Capabilities? {
        get { codableField(Keys.clientCapabilities, as: Client.Capabilities.self) }
        set { setCodableField(Keys.clientCapabilities, newValue) }
    }

    /// The identity of the client making this request.
    public var clientInfo: Client.Info? {
        get { codableField(Keys.clientInfo, as: Client.Info.self) }
        set { setCodableField(Keys.clientInfo, newValue) }
    }

    /// The identity of the server producing this result.
    public var serverInfo: Server.Info? {
        get { codableField(Keys.serverInfo, as: Server.Info.self) }
        set { setCodableField(Keys.serverInfo, newValue) }
    }

    /// The log level requested for this one request.
    ///
    /// Replaces `logging/setLevel`, which `2026-07-28` removes. A server must not emit
    /// `notifications/message` for a request that did not carry this field.
    public var logLevel: LogLevel? {
        get {
            guard let raw = fields[Keys.logLevel]?.stringValue else { return nil }
            return LogLevel(rawValue: raw)
        }
        set {
            if let newValue {
                fields[Keys.logLevel] = .string(newValue.rawValue)
            } else {
                fields.removeValue(forKey: Keys.logLevel)
            }
        }
    }

    /// The subscription this notification belongs to.
    public var subscriptionId: String? {
        get { fields[Keys.subscriptionId]?.stringValue }
        set {
            if let newValue {
                fields[Keys.subscriptionId] = .string(newValue)
            } else {
                fields.removeValue(forKey: Keys.subscriptionId)
            }
        }
    }
}
