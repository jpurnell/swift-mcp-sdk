import Foundation
import Testing

@testable import MCP

/// Per-request protocol carriage, introduced by MCP `2026-07-28` (SEP-2575).
///
/// The `initialize` handshake is removed. Every request now carries its own protocol version
/// and client capabilities in `_meta`, so any server instance can answer any request without
/// shared session state. These are namespaced keys on the existing open `_meta` object rather
/// than a new type, which is why they are modelled as accessors on `Metadata`.
@Suite("Protocol Meta Carriage Tests")
struct ProtocolMetaTests {

    @Test("The reserved keys use the specification's namespace")
    func testKeyNames() {
        #expect(Metadata.Keys.protocolVersion == "io.modelcontextprotocol/protocolVersion")
        #expect(Metadata.Keys.clientCapabilities == "io.modelcontextprotocol/clientCapabilities")
        #expect(Metadata.Keys.clientInfo == "io.modelcontextprotocol/clientInfo")
        #expect(Metadata.Keys.serverInfo == "io.modelcontextprotocol/serverInfo")
        #expect(Metadata.Keys.logLevel == "io.modelcontextprotocol/logLevel")
        #expect(Metadata.Keys.subscriptionId == "io.modelcontextprotocol/subscriptionId")
    }

    @Test("A request carries its protocol version and client capabilities")
    func testRequestCarriage() throws {
        var meta = Metadata()
        meta.protocolVersion = "2026-07-28"
        meta.clientCapabilities = .init(sampling: .init())
        meta.clientInfo = .init(name: "probe", version: "1.0.0")

        #expect(meta.protocolVersion == "2026-07-28")
        #expect(meta.clientCapabilities?.sampling == Client.Capabilities.Sampling())
        #expect(meta.clientInfo?.name == "probe")
    }

    @Test("Protocol carriage survives the wire format")
    func testRoundTrip() throws {
        var meta = Metadata()
        meta.protocolVersion = "2026-07-28"
        meta.clientCapabilities = .init(elicitation: .init())
        meta.clientInfo = .init(name: "probe", version: "2.1.0")
        meta.logLevel = .warning

        let data = try JSONEncoder().encode(meta)

        // Assert on the decoded object, not the raw text: Foundation's JSONEncoder escapes a
        // forward slash as `\/`, so the namespaced key appears as
        // `io.modelcontextprotocol\/protocolVersion` on the wire. That is valid JSON and decodes
        // correctly, but it makes substring assertions on these keys fragile.
        let asDictionary = try JSONDecoder().decode([String: Value].self, from: data)
        #expect(asDictionary[Metadata.Keys.protocolVersion] == .string("2026-07-28"))

        let decoded = try JSONDecoder().decode(Metadata.self, from: data)
        #expect(decoded.protocolVersion == "2026-07-28")
        #expect(decoded.clientCapabilities?.elicitation == Client.Capabilities.Elicitation())
        #expect(decoded.clientInfo?.version == "2.1.0")
        #expect(decoded.logLevel == .warning)
    }

    @Test("A result carries the server's identity")
    func testResultCarriesServerInfo() throws {
        var meta = Metadata()
        meta.serverInfo = .init(name: "my-server", version: "1.4.0")

        let decoded = try JSONDecoder().decode(Metadata.self, from: JSONEncoder().encode(meta))
        #expect(decoded.serverInfo?.name == "my-server")
        #expect(decoded.serverInfo?.version == "1.4.0")
    }

    @Test("A notification carries its subscription id")
    func testNotificationCarriesSubscriptionId() throws {
        var meta = Metadata()
        meta.subscriptionId = "sub-42"

        let decoded = try JSONDecoder().decode(Metadata.self, from: JSONEncoder().encode(meta))
        #expect(decoded.subscriptionId == "sub-42")
    }

    /// The reserved keys must not disturb `progressToken` or anything a caller put there.
    @Test("Protocol carriage coexists with progressToken and caller fields")
    func testCoexistsWithExistingFields() throws {
        var meta = Metadata(
            progressToken: .string("tok-1"),
            additionalFields: ["myApp/trace": .string("abc")]
        )
        meta.protocolVersion = "2026-07-28"

        #expect(meta.progressToken == .string("tok-1"))
        #expect(meta.fields["myApp/trace"] == .string("abc"))
        #expect(meta.protocolVersion == "2026-07-28")
    }

    /// Absent carriage must read as absent rather than as a default, so a 2025-era request is
    /// distinguishable from a 2026 one that forgot to declare itself.
    @Test("Absent carriage is nil, not a default")
    func testAbsentIsNil() {
        let meta = Metadata()
        #expect(meta.protocolVersion == nil)
        #expect(meta.clientCapabilities == nil)
        #expect(meta.clientInfo == nil)
        #expect(meta.serverInfo == nil)
        #expect(meta.logLevel == nil)
        #expect(meta.subscriptionId == nil)
    }

    /// Clearing a key removes it rather than writing a null, so the encoded object matches what
    /// a client on an earlier revision would send.
    @Test("Clearing carriage removes the key entirely")
    func testClearingRemovesKey() throws {
        var meta = Metadata()
        meta.protocolVersion = "2026-07-28"
        meta.protocolVersion = nil

        #expect(meta.fields[Metadata.Keys.protocolVersion] == nil)
        let data = try JSONEncoder().encode(meta)
        let asDictionary = try JSONDecoder().decode([String: Value].self, from: data)
        #expect(asDictionary[Metadata.Keys.protocolVersion] == nil)
        #expect(asDictionary.isEmpty, "no null placeholder is written for a cleared key")
    }
}
