import Foundation
import Testing

@testable import MCP

/// The result union for methods that can pause for input, from MCP `2026-07-28` (SEP-2322).
///
/// The schema names nine `*ResultResponse` envelopes, but only three carry a union:
/// `tools/call`, `prompts/get` and `resources/read` may return an ``InputRequiredResult``
/// instead of their normal result. The remaining envelopes are ordinary JSON-RPC responses that
/// `Response` already models, so one generic union covers the real distinction.
@Suite("MRTR Result Union Tests")
struct MRTRResultTests {

    @Test("A completed result decodes as complete")
    func testCompleteCase() throws {
        let value = MRTRResult<CallTool.Result>.complete(
            CallTool.Result(content: [], isError: false, resultType: .complete))

        let decoded = try JSONDecoder().decode(
            MRTRResult<CallTool.Result>.self, from: try JSONEncoder().encode(value))

        var isComplete = false
        if case .complete = decoded { isComplete = true }
        #expect(isComplete, "a tagged complete result must decode as complete")
    }

    @Test("An input-required result decodes as input required")
    func testInputRequiredCase() throws {
        let value = MRTRResult<CallTool.Result>.inputRequired(
            InputRequiredResult(
                inputRequests: ["need-roots": .listRoots(Empty())], requestState: "s1"))

        let decoded = try JSONDecoder().decode(
            MRTRResult<CallTool.Result>.self, from: try JSONEncoder().encode(value))

        guard case .inputRequired(let interim) = decoded else {
            Issue.record("expected an input-required result")
            return
        }
        #expect(interim.requestState == "s1")
        #expect(interim.inputRequests?.keys.contains("need-roots") == true)
    }

    /// The two cases are told apart by `resultType`, so a payload that omits it must read as
    /// complete — that is the rule for results from servers on earlier revisions.
    @Test("An untagged payload reads as complete")
    func testUntaggedIsComplete() throws {
        let json = #"{"content":[],"isError":false}"#
        let decoded = try JSONDecoder().decode(
            MRTRResult<CallTool.Result>.self, from: Data(json.utf8))

        var isComplete = false
        if case .complete = decoded { isComplete = true }
        #expect(isComplete, "an untagged result must be treated as complete")
    }

    /// A tagged interim result must not be mistaken for a completed one just because the
    /// concrete result type would also have decoded successfully.
    @Test("The tag decides, not whichever type happens to parse")
    func testTagDecides() throws {
        let json = #"{"resultType":"input_required","requestState":"s2"}"#
        let decoded = try JSONDecoder().decode(
            MRTRResult<ListTools.Result>.self, from: Data(json.utf8))

        guard case .inputRequired(let interim) = decoded else {
            Issue.record("the input_required tag must win")
            return
        }
        #expect(interim.requestState == "s2")
    }
}
