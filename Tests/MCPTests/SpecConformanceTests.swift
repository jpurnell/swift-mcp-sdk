import Foundation
import Testing

@testable import MCP

/// Decoding checked against the specification's own example payloads.
///
/// The fixtures in `Fixtures/` are copied verbatim from `schema/2026-07-28/examples` in the
/// `modelcontextprotocol/modelcontextprotocol` repository. They matter more than hand-written
/// fixtures because they are what the specification authors consider correct — a type that
/// round-trips our own idea of a payload proves only that we are self-consistent.
@Suite("Specification Conformance")
struct SpecConformanceTests {

    private func fixture(_ name: String) throws -> Data {
        let url = try #require(
            Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "json"),
            "fixture \(name).json is missing from the test bundle")
        return try Data(contentsOf: url)
    }

    @Test("The specification's DiscoverResult example decodes")
    func testDiscoverResult() throws {
        let result = try JSONDecoder().decode(Discover.Result.self, from: fixture("DiscoverResult"))

        #expect(result.supportedVersions == ["2026-07-28"])
        #expect(result.resultType == .complete)
        #expect(result.ttlMs == 3_600_000)
        #expect(result.cacheScope == .public)
        #expect(result._meta?.serverInfo?.name == "ExampleServer")
        #expect(result.instructions?.isEmpty == false)
    }

    @Test("The specification's ListToolsResult example decodes")
    func testListToolsResult() throws {
        let result = try JSONDecoder().decode(
            ListTools.Result.self, from: fixture("ListToolsResult"))

        #expect(result.resultType == .complete)
        #expect(result.tools.isEmpty == false)
        #expect(result.ttlMs != nil, "this fixture is the one carrying a ttl")
    }

    @Test("The specification's SubscriptionsListenResult example decodes")
    func testSubscriptionsListenResult() throws {
        let result = try JSONDecoder().decode(
            SubscriptionsListen.Result.self, from: fixture("SubscriptionsListenResult"))

        #expect(result.resultType == .complete)
        #expect(result._meta?.subscriptionId == "listen-1")
    }

    /// This is the fixture that matters most: `inputRequests` values are **full JSON-RPC request
    /// objects**, carrying `method` and `params`, not bare parameter objects. Decoding it is what
    /// proves the MRTR union matches the wire format rather than a plausible reading of it.
    @Test("The specification's InputRequiredResult example decodes")
    func testInputRequiredResult() throws {
        let result = try JSONDecoder().decode(
            InputRequiredResult.self, from: fixture("InputRequiredResult"))

        #expect(result.resultType == .inputRequired)
        #expect(result.requestState?.isEmpty == false)
        let requests = try #require(result.inputRequests)
        #expect(requests.count == 2, "the fixture carries an elicitation and a sampling request")

        // The kinds must survive. `Empty` accepts any object, so a union that falls through to
        // it would decode every entry as `.listRoots` and still look like a success — which is
        // precisely what a count-only assertion would miss.
        var kinds: Set<String> = []
        for request in requests.values {
            switch request {
            case .elicit: kinds.insert("elicit")
            case .createMessage: kinds.insert("createMessage")
            case .listRoots: kinds.insert("listRoots")
            }
        }
        #expect(
            kinds == ["elicit", "createMessage"],
            "decoded kinds were \(kinds.sorted()) — the fixture holds an elicitation and a sampling request")
    }

    @Test("The specification's CallToolResult example decodes")
    func testCallToolResult() throws {
        let result = try JSONDecoder().decode(
            CallTool.Result.self, from: fixture("CallToolResult"))
        #expect(result.resultType == .complete)
    }
}
