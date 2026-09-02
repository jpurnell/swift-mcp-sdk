import Foundation
import Testing

@testable import MCP

/// OpenTelemetry trace context propagation, documented by MCP `2026-07-28` as reserved `_meta`
/// keys.
///
/// Unlike the `io.modelcontextprotocol/` keys these are W3C names carried verbatim —
/// `traceparent`, `tracestate` and `baggage` — so a span crossing an MCP boundary keeps its
/// parent rather than starting a new trace at every hop.
@Suite("Trace Context Tests")
struct TraceContextTests {

    @Test("The keys are the W3C names, unnamespaced")
    func testKeyNames() {
        #expect(Metadata.Keys.traceparent == "traceparent")
        #expect(Metadata.Keys.tracestate == "tracestate")
        #expect(Metadata.Keys.baggage == "baggage")
    }

    @Test("Trace context round-trips through the wire format")
    func testRoundTrip() throws {
        var meta = Metadata()
        meta.traceparent = "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"
        meta.tracestate = "vendor=value"
        meta.baggage = "userId=alice"

        let decoded = try JSONDecoder().decode(Metadata.self, from: JSONEncoder().encode(meta))

        #expect(decoded.traceparent == "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01")
        #expect(decoded.tracestate == "vendor=value")
        #expect(decoded.baggage == "userId=alice")
    }

    /// Trace context is orthogonal to protocol carriage and must not disturb it — a request
    /// carries both, and losing either would be a silent failure rather than an error.
    @Test("Trace context coexists with protocol carriage")
    func testCoexistsWithProtocolCarriage() {
        var meta = Metadata()
        meta.protocolVersion = "2026-07-28"
        meta.traceparent = "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"

        #expect(meta.protocolVersion == "2026-07-28")
        #expect(meta.traceparent?.isEmpty == false)
        #expect(meta.fields.count == 2)
    }

    @Test("Absent trace context is nil, and clearing removes the key")
    func testAbsentAndCleared() throws {
        var meta = Metadata()
        #expect(meta.traceparent == nil)

        meta.traceparent = "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"
        meta.traceparent = nil

        #expect(meta.fields[Metadata.Keys.traceparent] == nil)
        let asDictionary = try JSONDecoder().decode(
            [String: Value].self, from: JSONEncoder().encode(meta))
        #expect(asDictionary.isEmpty)
    }
}
