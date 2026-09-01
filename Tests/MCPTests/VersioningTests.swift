import Testing

@testable import MCP

@Suite("Version Negotiation Tests")
struct VersioningTests {
    @Test("Client requests latest supported version")
    func testClientRequestsLatestSupportedVersion() {
        let clientVersion = Version.latest
        let negotiatedVersion = Version.negotiate(clientRequestedVersion: clientVersion)
        #expect(negotiatedVersion == Version.latest)
    }

    @Test("Client requests older supported version")
    func testClientRequestsOlderSupportedVersion() {
        let clientVersion = "2024-11-05"
        let negotiatedVersion = Version.negotiate(clientRequestedVersion: clientVersion)
        #expect(negotiatedVersion == "2024-11-05")
    }

    @Test("Client requests unsupported version")
    func testClientRequestsUnsupportedVersion() {
        let clientVersion = "2023-01-01"  // An unsupported version
        let negotiatedVersion = Version.negotiate(clientRequestedVersion: clientVersion)
        #expect(negotiatedVersion == Version.latest)
    }

    @Test("Client requests empty version string")
    func testClientRequestsEmptyVersionString() {
        let clientVersion = ""
        let negotiatedVersion = Version.negotiate(clientRequestedVersion: clientVersion)
        #expect(negotiatedVersion == Version.latest)
    }

    @Test("Client requests garbage version string")
    func testClientRequestsGarbageVersionString() {
        let clientVersion = "not-a-version"
        let negotiatedVersion = Version.negotiate(clientRequestedVersion: clientVersion)
        #expect(negotiatedVersion == Version.latest)
    }

    @Test("Server's supported versions correctly defined")
    func testServerSupportedVersions() {
        #expect(Version.supported.contains("2026-07-28"))
        #expect(Version.supported.contains("2025-11-25"))
        #expect(Version.supported.contains("2025-06-18"))
        #expect(Version.supported.contains("2025-03-26"))
        #expect(Version.supported.contains("2024-11-05"))
        #expect(Version.supported.count == 5)
    }

    @Test("Server's latest version is correct")
    func testServerLatestVersion() {
        #expect(Version.latest == "2026-07-28")
    }

    /// `latest` and `supported` must not drift apart. Declaring `latest` separately from the
    /// set makes that possible, so it is pinned rather than assumed.
    @Test("The latest version is a member of the supported set")
    func testLatestIsSupported() {
        #expect(Version.supported.contains(Version.latest))
    }

    /// Protocol versions are `YYYY-MM-DD`, so lexicographic order is chronological order.
    /// This is what previously made `supported.max()` the right definition of `latest`, and it
    /// still has to hold now that `latest` is declared directly.
    @Test("The latest version is the chronologically newest supported version")
    func testLatestIsNewest() {
        #expect(Version.latest == Version.supported.max())
    }

    @Test("Client requests the 2026-07-28 version")
    func testClientRequests2026_07_28Version() {
        let negotiatedVersion = Version.negotiate(clientRequestedVersion: "2026-07-28")
        #expect(negotiatedVersion == "2026-07-28")
    }

    /// A pre-2026 client must still negotiate its own revision, not be pushed forward to a
    /// version whose semantics it does not implement. This is what makes serving both
    /// revisions from one server possible.
    @Test("An older client still negotiates its own revision, not the latest")
    func testOlderClientKeepsItsRevision() {
        #expect(Version.negotiate(clientRequestedVersion: "2025-03-26") == "2025-03-26")
        #expect(Version.negotiate(clientRequestedVersion: "2024-11-05") == "2024-11-05")
    }

    @Test("Client requests new 2025-11-25 version")
    func testClientRequests2025_11_25Version() {
        let clientVersion = "2025-11-25"
        let negotiatedVersion = Version.negotiate(clientRequestedVersion: clientVersion)
        #expect(negotiatedVersion == "2025-11-25")
    }
}
