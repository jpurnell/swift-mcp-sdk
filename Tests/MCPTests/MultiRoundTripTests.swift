import Foundation
import Testing

@testable import MCP

/// Multi Round-Trip Requests, introduced by MCP `2026-07-28` (SEP-2322).
///
/// MRTR replaces server-initiated requests. Rather than the server pushing `roots/list`,
/// `sampling/createMessage` or `elicitation/create` down an open channel, it returns an
/// ``InputRequiredResult`` naming what it needs; the client answers by **retrying the original
/// request** with those responses attached. That is what lets the protocol be stateless — there
/// is no open channel to push down.
@Suite("Multi Round-Trip Request Tests")
struct MultiRoundTripTests {

    @Test("An input-required result is tagged as such")
    func testResultTypeTag() throws {
        let result = InputRequiredResult(
            inputRequests: ["roots": .listRoots(Empty())],
            requestState: "state-1"
        )
        #expect(result.resultType == .inputRequired, "the tag is what tells a client to retry")
    }

    @Test("Input requests round-trip, keyed by the server's identifiers")
    func testInputRequestsRoundTrip() throws {
        let result = InputRequiredResult(
            inputRequests: ["need-roots": .listRoots(Empty())],
            requestState: "opaque-server-state"
        )

        let decoded = try JSONDecoder().decode(
            InputRequiredResult.self, from: try JSONEncoder().encode(result))

        #expect(decoded.requestState == "opaque-server-state")
        #expect(decoded.inputRequests?.count == 1)
        #expect(decoded.inputRequests?.keys.contains("need-roots") == true)
        var isListRoots = false
        if case .listRoots = decoded.inputRequests?["need-roots"] { isListRoots = true }
        #expect(isListRoots, "the request kind was lost in the round trip")
    }

    /// The response keys must correspond to the request keys — that correspondence is the only
    /// thing tying an answer to the question it answers.
    @Test("Input responses round-trip under the same keys")
    func testInputResponsesRoundTrip() throws {
        let params = InputResponseRequestParams(
            inputResponses: ["need-roots": .listRoots(ListRoots.Result(roots: []))],
            requestState: "opaque-server-state"
        )

        let decoded = try JSONDecoder().decode(
            InputResponseRequestParams.self, from: try JSONEncoder().encode(params))

        #expect(decoded.requestState == "opaque-server-state")
        #expect(decoded.inputResponses?.count == 1)
        #expect(decoded.inputResponses?.keys.contains("need-roots") == true)
    }

    /// `requestState` is opaque to the client and must survive verbatim, because it is how the
    /// server correlates a retry with the work it had already done.
    @Test("Request state survives verbatim")
    func testRequestStateIsOpaque() throws {
        let awkward = "{\"nested\":\"json\",\"n\":1}"
        let result = InputRequiredResult(inputRequests: [:], requestState: awkward)
        let decoded = try JSONDecoder().decode(
            InputRequiredResult.self, from: try JSONEncoder().encode(result))
        #expect(decoded.requestState == awkward)
    }

    @Test("Each input request kind survives the round trip", arguments: ["roots", "elicit"])
    func testEachKind(kind: String) throws {
        let request: InputRequest
        switch kind {
        case "roots":
            request = .listRoots(Empty())
        default:
            request = .elicit(
                .form(
                    CreateElicitation.Parameters.FormParameters(
                        message: "Need a value",
                        requestedSchema: Elicitation.RequestSchema(properties: [:]))))
        }

        let result = InputRequiredResult(inputRequests: ["k": request], requestState: nil)
        let decoded = try JSONDecoder().decode(
            InputRequiredResult.self, from: try JSONEncoder().encode(result))
        #expect(decoded.inputRequests?.count == 1, "\(kind) was lost")
        #expect(decoded.inputRequests?.keys.first == "k")
    }
}
