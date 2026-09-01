import Foundation
import Testing

@testable import MCP

/// `subscriptions/listen`, introduced by MCP `2026-07-28` (SEP-2575).
///
/// It replaces the HTTP GET endpoint and the `resources/subscribe` / `resources/unsubscribe`
/// RPCs with a single long-lived POST-response stream that the client opts into. The server
/// acknowledges with the subset it agreed to honour — a client asking for more than the server
/// offers gets told, rather than silently receiving nothing.
@Suite("Subscriptions Tests")
struct SubscriptionsTests {

    @Test("The method is named subscriptions/listen")
    func testMethodName() {
        #expect(SubscriptionsListen.name == "subscriptions/listen")
    }

    @Test("A filter round-trips every notification kind")
    func testFilterRoundTrip() throws {
        let filter = SubscriptionFilter(
            toolsListChanged: true,
            promptsListChanged: false,
            resourcesListChanged: true,
            resourceSubscriptions: ["file:///a.txt", "file:///b.txt"]
        )

        let decoded = try JSONDecoder().decode(
            SubscriptionFilter.self, from: try JSONEncoder().encode(filter))

        #expect(decoded.toolsListChanged == true)
        #expect(decoded.promptsListChanged == false)
        #expect(decoded.resourcesListChanged == true)
        #expect(decoded.resourceSubscriptions == ["file:///a.txt", "file:///b.txt"])
    }

    /// `resourceSubscriptions` carries the URIs that `resources/subscribe` used to carry one at
    /// a time, so an empty array and an absent field must stay distinguishable: "subscribe to
    /// nothing" is not "do not subscribe".
    @Test("An empty subscription list is distinct from an absent one")
    func testEmptyIsNotAbsent() throws {
        let empty = SubscriptionFilter(resourceSubscriptions: [])
        let absent = SubscriptionFilter()

        let decodedEmpty = try JSONDecoder().decode(
            SubscriptionFilter.self, from: try JSONEncoder().encode(empty))
        let decodedAbsent = try JSONDecoder().decode(
            SubscriptionFilter.self, from: try JSONEncoder().encode(absent))

        #expect(decodedEmpty.resourceSubscriptions == [])
        #expect(decodedAbsent.resourceSubscriptions == nil)
    }

    @Test("The listen request carries the filter the client opts into")
    func testListenRequestParameters() throws {
        let params = SubscriptionsListen.Parameters(
            notifications: SubscriptionFilter(toolsListChanged: true))

        let decoded = try JSONDecoder().decode(
            SubscriptionsListen.Parameters.self, from: try JSONEncoder().encode(params))
        #expect(decoded.notifications.toolsListChanged == true)
    }

    /// The acknowledgement is what makes the opt-in honest: the server states the subset it
    /// will actually honour, which may be narrower than what was asked for.
    @Test("An acknowledgement may narrow what the client requested")
    func testAcknowledgementMayNarrow() throws {
        let requested = SubscriptionFilter(toolsListChanged: true, resourcesListChanged: true)
        let acknowledged = SubscriptionsAcknowledged.Parameters(
            notifications: SubscriptionFilter(toolsListChanged: true))

        let decoded = try JSONDecoder().decode(
            SubscriptionsAcknowledged.Parameters.self,
            from: try JSONEncoder().encode(acknowledged))

        #expect(requested.resourcesListChanged == true)
        #expect(
            decoded.notifications.resourcesListChanged == nil,
            "the server did not agree to resource list changes, and says so")
        #expect(decoded.notifications.toolsListChanged == true)
    }

    @Test("The listen result is tagged and carries its subscription stream identity")
    func testListenResult() throws {
        var meta = Metadata()
        meta.subscriptionId = "stream-7"
        let result = SubscriptionsListen.Result(resultType: .complete, _meta: meta)

        let decoded = try JSONDecoder().decode(
            SubscriptionsListen.Result.self, from: try JSONEncoder().encode(result))

        #expect(decoded.resultType == .complete)
        #expect(decoded._meta?.subscriptionId == "stream-7")
    }
}
