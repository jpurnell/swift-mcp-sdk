import Foundation
import Testing

@testable import MCP

/// Client-side caching hints introduced by MCP `2026-07-28` (SEP-2549).
///
/// The specification marks `ttlMs` and `cacheScope` as required on the list and read results.
/// They are modelled as optional here deliberately: the same Swift types serve clients on
/// 2025-era revisions, which must **not** receive these fields. The requirement is a protocol
/// obligation for a 2026-07-28 server, enforced where the response is composed, not a
/// constraint the type system can carry while both revisions are served.
@Suite("Cacheable Result Tests")
struct CacheableResultTests {

    @Test("CacheScope encodes as the wire strings the specification defines")
    func testCacheScopeWireForm() throws {
        #expect(CacheScope.public.rawValue == "public")
        #expect(CacheScope.private.rawValue == "private")

        let decoded = try JSONDecoder().decode(CacheScope.self, from: Data(#""private""#.utf8))
        #expect(decoded == .private)
    }

    @Test("ListTools result round-trips its caching hint")
    func testListToolsCachingHint() throws {
        let result = ListTools.Result(tools: [], ttlMs: 60_000, cacheScope: .public)

        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(ListTools.Result.self, from: data)

        #expect(decoded.ttlMs == 60_000)
        #expect(decoded.cacheScope == .public)
    }

    /// A result composed without a hint must not emit the keys at all — a 2025-era client
    /// should see exactly the payload it saw before.
    @Test("A result without a caching hint omits both keys")
    func testAbsentHintOmitsKeys() throws {
        let result = ListTools.Result(tools: [])

        let data = try JSONEncoder().encode(result)
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(!json.contains("ttlMs"))
        #expect(!json.contains("cacheScope"))
    }

    /// `ttlMs` of zero is meaningful — "immediately stale" — and must survive a round trip
    /// rather than being treated as absent.
    @Test("A zero ttlMs is preserved, not dropped as empty")
    func testZeroTTLIsPreserved() throws {
        let result = ListTools.Result(tools: [], ttlMs: 0, cacheScope: .private)

        let data = try JSONEncoder().encode(result)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("ttlMs"))

        let decoded = try JSONDecoder().decode(ListTools.Result.self, from: data)
        #expect(decoded.ttlMs == 0)
    }

    @Test("Every cacheable result type carries the hint", arguments: ["list", "read", "templates", "prompts"])
    func testAllCacheableResultsCarryTheHint(kind: String) throws {
        switch kind {
        case "list":
            let result = ListResources.Result(resources: [], ttlMs: 1, cacheScope: .private)
            #expect(result.ttlMs == 1 && result.cacheScope == .private)
        case "read":
            let result = ReadResource.Result(contents: [], ttlMs: 2, cacheScope: .public)
            #expect(result.ttlMs == 2 && result.cacheScope == .public)
        case "templates":
            let result = ListResourceTemplates.Result(templates: [], ttlMs: 3, cacheScope: .private)
            #expect(result.ttlMs == 3 && result.cacheScope == .private)
        default:
            let result = ListPrompts.Result(prompts: [], ttlMs: 4, cacheScope: .public)
            #expect(result.ttlMs == 4 && result.cacheScope == .public)
        }
    }
}
