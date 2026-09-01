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

    /// A result composed without a tag must emit no key at all, so a client on an earlier
    /// revision sees the payload it has always seen.
    @Test("An untagged result omits the key")
    func testUntaggedOmitsKey() throws {
        let value = ListTools.Result(tools: [])
        let data = try JSONEncoder().encode(value)
        let asDictionary = try JSONDecoder().decode([String: Value].self, from: data)
        #expect(asDictionary["resultType"] == nil)
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
