import Foundation
import Testing

@testable import MCP

/// `server/discover`, introduced by MCP `2026-07-28` (SEP-2575).
///
/// Servers **MUST** implement it. Clients **MAY** call it before any other request to choose a
/// protocol version up front, or use it as a backward-compatibility probe — which is what makes
/// serving `2026-07-28` and earlier revisions from one implementation possible.
@Suite("Server Discover Tests")
struct DiscoverTests {

    @Test("The method is named server/discover")
    func testMethodName() {
        #expect(Discover.name == "server/discover")
    }

    @Test("A discover result advertises every supported version")
    func testAdvertisesSupportedVersions() throws {
        let result = Discover.Result(
            supportedVersions: Version.supported.sorted(by: >),
            capabilities: .init(tools: .init(listChanged: true)),
            ttlMs: 3_600_000,
            cacheScope: .public
        )

        #expect(result.supportedVersions.contains("2026-07-28"))
        #expect(result.supportedVersions.contains("2025-03-26"))
        #expect(result.supportedVersions.first == "2026-07-28", "newest first")
    }

    @Test("A discover result round-trips through the wire format")
    func testRoundTrip() throws {
        let result = Discover.Result(
            supportedVersions: ["2026-07-28", "2025-11-25"],
            capabilities: .init(
                extensions: ["io.modelcontextprotocol/tasks": .object(["enabled": .bool(true)])],
                tools: .init(listChanged: true)
            ),
            instructions: "Greets people by name.",
            ttlMs: 60_000,
            cacheScope: .private
        )

        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(Discover.Result.self, from: data)

        #expect(decoded.supportedVersions == ["2026-07-28", "2025-11-25"])
        #expect(decoded.capabilities.tools?.listChanged == true)
        #expect(
            decoded.capabilities.extensions?["io.modelcontextprotocol/tasks"]
                == .object(["enabled": .bool(true)]))
        #expect(decoded.instructions == "Greets people by name.")
        #expect(decoded.ttlMs == 60_000)
        #expect(decoded.cacheScope == .private)
    }

    /// The specification marks `ttlMs` and `cacheScope` required on this result, so it is a
    /// `CacheableResult` like the list and read results.
    @Test("A discover result is cacheable")
    func testIsCacheable() {
        let result = Discover.Result(
            supportedVersions: [Version.latest],
            capabilities: .init(),
            ttlMs: 0,
            cacheScope: .public
        )
        let cacheable: any CacheableResult = result
        #expect(cacheable.ttlMs == 0)
        #expect(cacheable.cacheScope == .public)
    }

    /// Discovery is what lets a client pick a version without an `initialize` handshake, so the
    /// advertised set must agree with what negotiation will actually accept.
    @Test("Every advertised version is one negotiation accepts")
    func testAdvertisedVersionsAreNegotiable() {
        let advertised = Version.supported.sorted(by: >)
        for version in advertised {
            #expect(Version.negotiate(clientRequestedVersion: version) == version)
        }
    }
}
