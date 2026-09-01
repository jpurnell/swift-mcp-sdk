import Foundation

/// The notification kinds a client opts into on a subscription stream.
///
/// Introduced by MCP `2026-07-28` (SEP-2575). Each field is optional and tri-state: absent
/// means the client expressed no interest, which is not the same as `false`. That distinction
/// matters in an acknowledgement, where the server states the subset it agreed to honour and an
/// absent field means "not granted".
public struct SubscriptionFilter: Hashable, Codable, Sendable {
    /// Receive `notifications/tools/list_changed`.
    public var toolsListChanged: Bool?
    /// Receive `notifications/prompts/list_changed`.
    public var promptsListChanged: Bool?
    /// Receive `notifications/resources/list_changed`.
    public var resourcesListChanged: Bool?
    /// Receive `notifications/resources/updated` for these resource URIs.
    ///
    /// Replaces the former `resources/subscribe` RPC, which carried one URI per call. An empty
    /// array means "subscribe to no resources" and is deliberately distinct from `nil`, which
    /// means the client did not ask about resource subscriptions at all.
    public var resourceSubscriptions: [String]?

    public init(
        toolsListChanged: Bool? = nil,
        promptsListChanged: Bool? = nil,
        resourcesListChanged: Bool? = nil,
        resourceSubscriptions: [String]? = nil
    ) {
        self.toolsListChanged = toolsListChanged
        self.promptsListChanged = promptsListChanged
        self.resourcesListChanged = resourcesListChanged
        self.resourceSubscriptions = resourceSubscriptions
    }
}

/// Opens a long-lived stream for server-to-client change notifications.
///
/// Introduced by MCP `2026-07-28` (SEP-2575), replacing the HTTP GET endpoint and the
/// `resources/subscribe` / `resources/unsubscribe` RPCs. The client opts into specific
/// notification kinds; the server acknowledges with the subset it will honour.
///
/// Request-scoped notifications such as `notifications/progress` and `notifications/message`
/// continue to flow on the response stream of the request they belong to, **not** here.
public enum SubscriptionsListen: Method {
    public static let name: String = "subscriptions/listen"

    public struct Parameters: Hashable, Codable, Sendable {
        /// The notifications the client opts into on this stream.
        public var notifications: SubscriptionFilter
        /// Metadata for this request, carrying its protocol version and client capabilities.
        public var _meta: Metadata?

        public init(notifications: SubscriptionFilter, _meta: Metadata? = nil) {
            self.notifications = notifications
            self._meta = _meta
        }
    }

    public struct Result: Hashable, Codable, Sendable {
        /// Tells the client how to parse this result.
        public var resultType: ResultType?
        /// Metadata carrying the subscription stream's identifier, which tags every
        /// notification that arrives on it.
        public var _meta: Metadata?

        public init(resultType: ResultType? = nil, _meta: Metadata? = nil) {
            self.resultType = resultType
            self._meta = _meta
        }
    }
}

/// The server's acknowledgement of what it will actually send on a subscription stream.
///
/// This is what makes the opt-in honest: a client may ask for more than the server offers, and
/// the acknowledgement narrows the set rather than leaving the client waiting for notifications
/// that will never arrive.
public enum SubscriptionsAcknowledged {
    public static let name: String = "notifications/subscriptions/acknowledged"

    public struct Parameters: Hashable, Codable, Sendable {
        /// The subset of requested notification kinds the server agreed to honour.
        public var notifications: SubscriptionFilter
        /// Metadata carrying the subscription identifier this acknowledgement belongs to.
        public var _meta: Metadata?

        public init(notifications: SubscriptionFilter, _meta: Metadata? = nil) {
            self.notifications = notifications
            self._meta = _meta
        }
    }
}
