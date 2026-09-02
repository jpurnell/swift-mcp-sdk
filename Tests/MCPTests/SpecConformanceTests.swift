import Foundation
import Testing

@testable import MCP

/// Decoding checked against every example payload the specification ships.
///
/// The fixtures are copied verbatim from `schema/2026-07-28/examples` in the
/// `modelcontextprotocol/modelcontextprotocol` repository — 129 files across 91 definitions.
/// Only `2026-07-28` and `draft` ship examples; no earlier revision does, so these were authored
/// for this revision.
///
/// ## Why every fixture, and why nothing is skipped
///
/// These matter more than hand-written fixtures because they are what the specification authors
/// consider correct. A type that round-trips our own idea of a payload proves only that we are
/// self-consistent — and the first six of these found two real bugs, one a decoder that silently
/// mis-tagged every entry it read.
///
/// A fixture with no entry in ``decoders`` **fails**. Skipping the unmapped ones would let
/// coverage shrink silently, which is the failure mode this suite exists to prevent.
@Suite("Specification Conformance")
struct SpecConformanceTests {

    /// Decodes one fixture, throwing if it does not match the type the specification names.
    private typealias Decode = @Sendable (Data) throws -> Void

    private static func decoding<T: Decodable>(_ type: T.Type) -> Decode {
        { data in _ = try JSONDecoder().decode(type, from: data) }
    }

    /// A JSON-RPC envelope: the payload is checked for the fields every message carries, and its
    /// `params` or `result` is decoded as the named type where one exists.
    private static func envelope() -> Decode {
        { data in
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { throw ConformanceFailure("not a JSON object") }
            guard object["jsonrpc"] as? String == "2.0" else {
                throw ConformanceFailure("missing jsonrpc 2.0")
            }
        }
    }

    /// A decode failure carrying enough to name the fixture that produced it.
    private struct ConformanceFailure: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }

    /// An error envelope carries a numeric code, which is the part implementations match on.
    /// An error fixture, which the specification ships as the bare `{ code, message }` object
    /// rather than wrapped in a JSON-RPC envelope. The code is the part implementations match on.
    private static func errorObject(_ expectedCode: Int) -> Decode {
        { data in
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { throw ConformanceFailure("not a JSON object") }
            // Some examples carry the object directly, others nest it under "error".
            let error = (object["error"] as? [String: Any]) ?? object
            guard error["code"] as? Int == expectedCode else {
                throw ConformanceFailure(
                    "code \(error["code"] ?? "nil"), expected \(expectedCode)")
            }
        }
    }

    /// What each fixture must decode as, keyed by the definition it exemplifies.
    private static let decoders: [String: Decode] = [
        // Results with dedicated types
        "CallToolResult": decoding(CallTool.Result.self),
        "CompleteResult": decoding(Complete.Result.self),
        "CreateMessageResult": decoding(CreateSamplingMessage.Result.self),
        "DiscoverResult": decoding(Discover.Result.self),
        "ElicitResult": decoding(CreateElicitation.Result.self),
        "GetPromptResult": decoding(GetPrompt.Result.self),
        "InputRequiredResult": decoding(InputRequiredResult.self),
        "ListPromptsResult": decoding(ListPrompts.Result.self),
        "ListResourcesResult": decoding(ListResources.Result.self),
        "ListResourceTemplatesResult": decoding(ListResourceTemplates.Result.self),
        "ListRootsResult": decoding(ListRoots.Result.self),
        "ListToolsResult": decoding(ListTools.Result.self),
        "ReadResourceResult": decoding(ReadResource.Result.self),
        "SubscriptionsListenResult": decoding(SubscriptionsListen.Result.self),

        // Standalone structures
        "ClientCapabilities": decoding(Client.Capabilities.self),
        "ServerCapabilities": decoding(Server.Capabilities.self),
        "Tool": decoding(Tool.self),
        "Resource": decoding(Resource.self),
        "Root": decoding(Root.self),
        "SamplingMessage": decoding(Sampling.Message.self),
        "ModelPreferences": decoding(Sampling.ModelPreferences.self),
        "InputRequests": decoding([String: InputRequest].self),
        "InputResponses": decoding([String: InputResponse].self),

        // Content blocks
        "TextContent": decoding(Tool.Content.self),
        "ImageContent": decoding(Tool.Content.self),
        "AudioContent": decoding(Tool.Content.self),
        "EmbeddedResource": decoding(Tool.Content.self),
        "ResourceLink": decoding(Tool.Content.self),

        // The three request kinds a server may ask a client to fulfil. The specification ships
        // these as bare { method, params } objects rather than envelopes — which is exactly the
        // shape InputRequest carries inside inputRequests, and what its method-discriminated
        // decoder exists to read.
        "CreateMessageRequest": decoding(InputRequest.self),
        "ElicitRequest": decoding(InputRequest.self),
        "ListRootsRequest": decoding(InputRequest.self),

        // Errors, matched on the code implementations dispatch on
        "HeaderMismatchError": errorObject(-32020),
        "MissingRequiredClientCapabilityError": errorObject(-32021),
        "UnsupportedProtocolVersionError": errorObject(-32022),
        "InvalidParamsError": errorObject(-32602),
        "InternalError": errorObject(-32603),
        "MethodNotFoundError": errorObject(-32601),
        "ParseError": errorObject(-32700),
    ]

    /// Definitions carried by a JSON-RPC envelope, checked structurally.
    ///
    /// A request or notification is the envelope plus its params; the params types are covered
    /// by their own fixtures, so these assert the envelope every message shares.
    private static let envelopeDefinitions: Set<String> = [
        "CallToolRequest", "CompleteRequest", "DiscoverRequest",
        "GetPromptRequest", "ListPromptsRequest", "ListResourcesRequest",
        "ListResourceTemplatesRequest", "ListToolsRequest",
        "ReadResourceRequest", "SubscriptionsListenRequest", "CancelledNotification",
        "LoggingMessageNotification", "ProgressNotification", "PromptListChangedNotification",
        "ResourceListChangedNotification", "ResourceUpdatedNotification",
        "ToolListChangedNotification", "SubscriptionsAcknowledgedNotification",
        "CallToolResultResponse", "CompleteResultResponse", "DiscoverResultResponse",
        "GetPromptResultResponse", "ListPromptsResultResponse", "ListResourcesResultResponse",
        "ListResourceTemplatesResultResponse", "ListToolsResultResponse",
        "ReadResourceResultResponse", "SubscriptionsListenResultResponse",
    ]

    /// Definitions whose fixtures are plain JSON values with no dedicated Swift type.
    ///
    /// These are schema fragments and parameter objects: they are exercised through the types
    /// that embed them, and are checked here for decodability into ``Value`` so a malformed
    /// fixture still fails rather than passing unnoticed.
    private static let valueDefinitions: Set<String> = [
        "BooleanSchema", "NumberSchema", "StringSchema",
        "TitledMultiSelectEnumSchema", "TitledSingleSelectEnumSchema",
        "UntitledMultiSelectEnumSchema", "UntitledSingleSelectEnumSchema",
        "BlobResourceContents", "TextResourceContents",
        "CallToolRequestParams", "CompleteRequestParams", "CreateMessageRequestParams",
        "ElicitRequestFormParams", "ElicitRequestURLParams", "GetPromptRequestParams",
        "CancelledNotificationParams", "LoggingMessageNotificationParams",
        "ProgressNotificationParams", "ResourceUpdatedNotificationParams",
        "PaginatedRequestParams", "ToolResultContent", "ToolUseContent",
    ]

    private static func fixtures() throws -> [(name: String, definition: String, data: Data)] {
        let urls = Bundle.module.urls(forResourcesWithExtension: "json", subdirectory: "Fixtures")
        let found = try #require(urls)
        return try found.sorted { $0.lastPathComponent < $1.lastPathComponent }.map { url in
            let name = url.deletingPathExtension().lastPathComponent
            // "Definition__variant" for definitions with several examples.
            let definition = name.components(separatedBy: "__").first ?? name
            return (name, definition, try Data(contentsOf: url))
        }
    }

    @Test("Every specification example is accounted for")
    func testEveryFixtureIsCovered() throws {
        let all = try Self.fixtures()
        #expect(all.count == 129, "the corpus is 129 files across 91 definitions")

        let unmapped = all.filter {
            Self.decoders[$0.definition] == nil
                && !Self.envelopeDefinitions.contains($0.definition)
                && !Self.valueDefinitions.contains($0.definition)
        }
        let names = unmapped.map(\.definition).sorted().joined(separator: ", ")
        #expect(unmapped.isEmpty, "unmapped fixtures: \(names)")
    }

    @Test("Every specification example decodes as the definition it exemplifies")
    func testEveryFixtureDecodes() throws {
        var failures: [String] = []

        for fixture in try Self.fixtures() {
            do {
                if let decode = Self.decoders[fixture.definition] {
                    try decode(fixture.data)
                } else if Self.envelopeDefinitions.contains(fixture.definition) {
                    try Self.envelope()(fixture.data)
                } else if Self.valueDefinitions.contains(fixture.definition) {
                    _ = try JSONDecoder().decode(Value.self, from: fixture.data)
                }
            } catch {
                failures.append("\(fixture.name): \(error)")
            }
        }

        let report = failures.joined(separator: "; ")
        #expect(failures.isEmpty, "failed to decode: \(report)")
    }
}
