import Foundation
import Testing

@testable import MCP

/// The specification attaches a typed `data` object to several errors: the capabilities a
/// request needed, the URI that was not found, the versions a server will actually serve.
///
/// ``MCPError``'s other cases carry a free-text detail only, which cannot express any of those
/// without inventing a string format the receiver would have to parse back. These tests pin the
/// structured payload against the shapes the specification's own examples use.
@Suite("Structured error data")
struct StructuredErrorDataTests {

    private func encoded(_ error: MCPError) throws -> [String: Any] {
        let data = try JSONEncoder().encode(error)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// `MissingRequiredClientCapabilityError.json` in the specification carries
    /// `data.requiredCapabilities` as a `ClientCapabilities` object — `{"elicitation": {}}` —
    /// not a list of names. The object shape is what lets a client merge the answer into what it
    /// already declares and retry; a list would have to be translated first.
    @Test("A missing-capability error names the capabilities as an object")
    func testMissingCapabilityCarriesCapabilityObject() throws {
        let error = MCPError.missingRequiredClientCapability(requiring: ["sampling"])
        #expect(error.code == -32021)

        let json = try encoded(error)
        let data = try #require(json["data"] as? [String: Any])
        let required = try #require(data["requiredCapabilities"] as? [String: Any])
        #expect(required["sampling"] as? [String: Any] != nil, "each capability is an object")
    }

    /// SEP-2164: the URI belongs in `data`, so a client handling several reads at once can tell
    /// which one was refused without correlating by request id.
    @Test("A resource-not-found error carries the URI it refused")
    func testResourceNotFoundCarriesURI() throws {
        let error = MCPError.resourceNotFound(uri: "test://nonexistent")
        #expect(error.code == -32602)

        let json = try encoded(error)
        let data = try #require(json["data"] as? [String: Any])
        #expect(data["uri"] as? String == "test://nonexistent")
    }

    /// `supported` alone tells a client "no" without saying which of its attempts was refused.
    @Test("An unsupported-version error echoes both requested and supported")
    func testUnsupportedVersionCarriesBothSides() throws {
        let error = MCPError.unsupportedProtocolVersion(
            requested: "1900-01-01", supported: ["2026-07-28", "2025-11-25"])
        #expect(error.code == -32022)

        let json = try encoded(error)
        let data = try #require(json["data"] as? [String: Any])
        #expect(data["requested"] as? String == "1900-01-01")
        #expect(data["supported"] as? [String] == ["2026-07-28", "2025-11-25"])
    }

    /// A receiver must be able to read the payload back, or carrying it is pointless.
    @Test("A structured payload survives a round trip")
    func testStructuredPayloadRoundTrips() throws {
        let original = MCPError.missingRequiredClientCapability(requiring: ["elicitation"])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(MCPError.self, from: data)

        #expect(decoded.code == -32021)
        let payload = try #require(decoded.structuredData)
        #expect(payload["requiredCapabilities"]?.objectValue?["elicitation"] != nil)
    }

    /// The free-text cases are unchanged: a detail string still encodes as `data.detail`, and
    /// nothing about the structured payload leaks into errors that do not have one.
    @Test("An error with only a detail is unaffected")
    func testDetailOnlyErrorUnchanged() throws {
        let json = try encoded(MCPError.invalidParams("bad"))
        let data = try #require(json["data"] as? [String: Any])
        #expect(data["detail"] as? String == "bad")
        #expect(MCPError.invalidParams("bad").structuredData == nil)
    }
}

extension StructuredErrorDataTests {
    /// SEP-2663 names an extension under `extensions`, where a client declares it — not at the
    /// top level, which would produce an object the client cannot merge into what it sends.
    @Test("A missing-extension error nests it the way capabilities are declared")
    func testMissingExtensionIsNested() throws {
        let error = MCPError.missingRequiredClientCapability(
            requiringExtensions: ["io.modelcontextprotocol/tasks"])
        #expect(error.code == -32021)

        let json = try encoded(error)
        let data = try #require(json["data"] as? [String: Any])
        let required = try #require(data["requiredCapabilities"] as? [String: Any])
        let extensions = try #require(required["extensions"] as? [String: Any])
        #expect(Array(extensions.keys) == ["io.modelcontextprotocol/tasks"])
        #expect(extensions["io.modelcontextprotocol/tasks"] as? [String: Any] != nil)
    }
}
