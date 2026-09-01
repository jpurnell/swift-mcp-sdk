import Foundation
import Testing

@testable import MCP

/// Errors introduced by MCP `2026-07-28` (SEP-2575), and the code-allocation policy that
/// revision defines.
///
/// The JSON-RPC server-error range is partitioned: `-32000` to `-32019` stays
/// implementation-defined, with existing SDK usage grandfathered, and `-32020` to `-32099` is
/// reserved for the specification.
@Suite("Protocol Error Tests")
struct ProtocolErrorTests {

    @Test("The new errors use the codes the specification assigns")
    func testCodes() {
        #expect(MCPError.headerMismatch(nil).code == -32020)
        #expect(MCPError.missingRequiredClientCapability(nil).code == -32021)
        #expect(MCPError.unsupportedProtocolVersion(nil).code == -32022)
    }

    @Test("Each new error carries a usable description")
    func testDescriptions() {
        let error = MCPError.unsupportedProtocolVersion("2027-01-01")
        #expect(error.errorDescription?.contains("2027-01-01") == true)
        #expect(MCPError.headerMismatch(nil).errorDescription?.isEmpty == false)
        #expect(MCPError.missingRequiredClientCapability(nil).errorDescription?.isEmpty == false)
    }

    @Test("The new errors round-trip through the wire format")
    func testRoundTrip() throws {
        let error = MCPError.unsupportedProtocolVersion("2027-01-01")
        let data = try JSONEncoder().encode(error)
        let decoded = try JSONDecoder().decode(MCPError.self, from: data)
        #expect(decoded.code == -32022)
    }

    /// The grandfathered implementation-defined codes must stay where they are; moving them
    /// would break every consumer matching on them.
    @Test("Grandfathered implementation codes are unchanged")
    func testGrandfatheredCodesUnchanged() {
        #expect(MCPError.connectionClosed.code == -32000)
        #expect(MCPError.transportError(URLError(.badURL)).code == -32001)
    }

    /// `urlElicitationRequired` was assigned -32042, inside the range 2026-07-28 reserves for
    /// the specification. It is moved into the implementation-defined range rather than
    /// removed: URL-mode elicitation still exists, even though the revision removed the
    /// `URLElicitationRequiredError` definition and the `elicitationId` field.
    @Test("urlElicitationRequired no longer squats in the reserved range")
    func testUrlElicitationRenumbered() {
        let error = MCPError.urlElicitationRequired(message: "sign in", elicitations: [])
        #expect(error.code == -32003)
        #expect(error.code > -32020, "it must sit in the implementation-defined range")
    }

    /// Implementation-defined codes must not collide with each other either. -32002 is already
    /// StatelessHTTPServerTransport's request-cancelled code, and it was also the resource
    /// not-found code before this revision moved that to -32602 — so a peer on an earlier
    /// revision still sends it with that older meaning.
    @Test("No two implementation-defined codes collide")
    func testImplementationCodesAreDistinct() {
        let codes = [
            MCPError.connectionClosed.code,
            MCPError.transportError(URLError(.badURL)).code,
            MCPError.urlElicitationRequired(message: "x", elicitations: []).code,
        ]
        #expect(Set(codes).count == codes.count, "each case needs its own code")
        #expect(!codes.contains(-32002), "-32002 is taken by request-cancelled and by legacy resource-not-found")
    }

    /// Codes the specification reserves must not collide with codes this SDK assigns itself.
    @Test("No implementation-defined code intrudes on the reserved range")
    func testNoCollisionWithReservedRange() {
        let implementationDefined = [
            MCPError.connectionClosed.code,
            MCPError.transportError(URLError(.badURL)).code,
            MCPError.urlElicitationRequired(message: "x", elicitations: []).code,
        ]
        for code in implementationDefined {
            #expect(code > -32020, "\(code) is inside the specification-reserved range")
        }
    }
}
