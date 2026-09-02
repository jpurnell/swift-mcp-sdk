import Foundation
import Testing

@testable import MCP

/// Result tagging, introduced by MCP `2026-07-28` (SEP-2322).
///
/// Every result carries a `resultType` telling the client how to parse it. A server on this
/// revision **must** send it; a client receiving a result from an earlier-revision server, where
/// the field is absent, **must** treat it as `complete`.
@Suite("Result Type Tests")
struct ResultTypeTests {

    @Test("The wire values match the specification")
    func testWireValues() throws {
        #expect(ResultType.complete.rawValue == "complete")
        #expect(ResultType.inputRequired.rawValue == "input_required")

        let decoded = try JSONDecoder().decode(ResultType.self, from: Data(#""input_required""#.utf8))
        #expect(decoded == .inputRequired)
    }

    /// The specification says an absent `resultType` means `complete`. That rule belongs with
    /// the type, so every reader gets it rather than each call site reimplementing it.
    @Test("An absent result type resolves to complete")
    func testAbsentResolvesToComplete() {
        #expect(ResultType.resolving(nil) == .complete)
        #expect(ResultType.resolving(.inputRequired) == .inputRequired)
    }

    @Test("Results round-trip their result type", arguments: ["tools", "prompts", "resources", "discover"])
    func testResultsCarryResultType(kind: String) throws {
        switch kind {
        case "tools":
            let value = ListTools.Result(tools: [], resultType: .complete)
            let decoded = try JSONDecoder().decode(
                ListTools.Result.self, from: try JSONEncoder().encode(value))
            #expect(decoded.resultType == .complete)
        case "prompts":
            let value = ListPrompts.Result(prompts: [], resultType: .complete)
            let decoded = try JSONDecoder().decode(
                ListPrompts.Result.self, from: try JSONEncoder().encode(value))
            #expect(decoded.resultType == .complete)
        case "resources":
            let value = ReadResource.Result(contents: [], resultType: .complete)
            let decoded = try JSONDecoder().decode(
                ReadResource.Result.self, from: try JSONEncoder().encode(value))
            #expect(decoded.resultType == .complete)
        default:
            let value = Discover.Result(
                supportedVersions: [Version.latest], capabilities: .init(), resultType: .complete)
            let decoded = try JSONDecoder().decode(
                Discover.Result.self, from: try JSONEncoder().encode(value))
            #expect(decoded.resultType == .complete)
        }
    }

    /// A result can still be built with no tag — but it has to be asked for now.
    ///
    /// This test used to assert the opposite, that a result composed without arguments emitted
    /// no `resultType` key, "so a client on an earlier revision sees the payload it has always
    /// seen". **That default was wrong for `2026-07-28`**, which requires the field on every
    /// result and says a server implementing the revision MUST include it. Leaving it to each
    /// construction site made conformance something a caller had to remember, and the one place
    /// that forgot — `completion/complete` — produced a schema-invalid response that nothing
    /// local caught.
    ///
    /// The original concern does not survive scrutiny either: an extra key is not a hazard to a
    /// pre-2026 client, which ignores fields it does not know, and the specification's own rule
    /// that an *absent* tag means `complete` says the field is expected to be there.
    ///
    /// So the default moved and the capability stayed: passing `nil` explicitly still omits it.
    @Test("A tag can still be omitted, by asking for it")
    func testTagCanBeOmittedExplicitly() throws {
        let value = ListTools.Result(tools: [], resultType: nil)
        let data = try JSONEncoder().encode(value)
        let asDictionary = try JSONDecoder().decode([String: Value].self, from: data)
        #expect(asDictionary["resultType"] == nil)

        let defaulted = ListTools.Result(tools: [])
        let defaultedData = try JSONEncoder().encode(defaulted)
        let defaultedDictionary = try JSONDecoder().decode(
            [String: Value].self, from: defaultedData)
        #expect(defaultedDictionary["resultType"] == .string("complete"))
    }

    /// An unrecognised tag from a future revision must decode rather than throw — the client
    /// can still read the rest of the result.
    @Test("An unknown result type decodes without throwing")
    func testUnknownTypeIsTolerated() throws {
        let json = #"{"tools":[],"resultType":"something_new"}"#
        let decoded = try JSONDecoder().decode(ListTools.Result.self, from: Data(json.utf8))
        #expect(decoded.resultType == nil, "an unrecognised tag reads as absent, not as a failure")
        #expect(decoded.tools.isEmpty)
    }
}

extension ResultTypeTests {
    /// `2026-07-28` requires `resultType` on **every** result — `CallToolResult`,
    /// `CompleteResult`, `GetPromptResult`, the list results, all of them — and says a server
    /// implementing the revision MUST include it.
    ///
    /// Defaulting it to `nil` made conformance something each caller had to remember at each
    /// construction site, and one that forgot produced a schema-invalid response that nothing
    /// local would catch. `complete` is the right default because it is what an absent field
    /// means to a client on an earlier revision; the two shapes that are *not* complete —
    /// `InputRequiredResult` and `CreateTaskResult` — set their own tag and cannot be built
    /// without it.
    @Test("Every result tags itself complete unless told otherwise")
    func testResultsDefaultToComplete() throws {
        #expect(CallTool.Result(content: []).resultType == .complete)
        #expect(GetPrompt.Result(messages: []).resultType == .complete)
        #expect(ListTools.Result(tools: []).resultType == .complete)
        #expect(ListPrompts.Result(prompts: []).resultType == .complete)
        #expect(ListResources.Result(resources: []).resultType == .complete)
        #expect(ReadResource.Result(contents: []).resultType == .complete)
        #expect(
            Complete.Result(completion: .init(values: [])).resultType == .complete,
            "the one that was missed, and the reason the default moved")
    }

    /// The two that are not complete keep their own tag.
    @Test("The interim shapes are not overridden by the default")
    func testInterimShapesKeepTheirTag() {
        #expect(InputRequiredResult().resultType == .inputRequired)
        #expect(
            CreateTaskResult(task: .init(
                taskId: "t", status: .working, createdAt: "now", lastUpdatedAt: "now",
                ttlMs: nil)).resultType == .task)
    }
}
