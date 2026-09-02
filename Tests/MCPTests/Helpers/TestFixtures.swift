import Foundation
import Testing

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

// MARK: - Values written as literals in a test

/// A `URL` written as a literal by the author of a test.
///
/// `URL(string:)` is failable because a URL can arrive from anywhere. A literal in a test did
/// not: it came from whoever wrote the line, and a typo in it is a defect in the test rather
/// than a condition the test should handle. Force-unwrapping says that — and says it by
/// trapping, which takes down the whole test run and reports the crash at the unwrap rather than
/// naming the string that was wrong.
///
/// This says the same thing once, where the safety audit can see it, and fails the one test that
/// holds the bad literal:
///
/// ```swift
/// let endpoint = testURL("https://localhost:8080/test")
/// ```
///
/// The sentinel returned after a recorded failure exists so the signature can stay
/// non-optional; a test that reaches it has already failed, and `about:blank` reaches nothing.
///
/// - Parameters:
///   - string: The URL literal.
///   - sourceLocation: Where the literal was written, so a failure names that line.
/// - Returns: The parsed URL, or an inert sentinel once the failure has been recorded.
func testURL(_ string: String, sourceLocation: SourceLocation = #_sourceLocation) -> URL {
    guard let url = URL(string: string) else {
        Issue.record("Not a valid URL literal: \(string)", sourceLocation: sourceLocation)
        return URL(string: "about:blank") ?? URL(fileURLWithPath: "/")
    }
    return url
}

/// An `HTTPURLResponse` for a request a test is answering.
///
/// `HTTPURLResponse.init` is failable on the URL and the version string alone, both of which a
/// test supplies as literals. Same reasoning as ``testURL(_:sourceLocation:)``: state it once
/// rather than trapping at every mock.
///
/// - Parameters:
///   - url: The URL the response is for.
///   - statusCode: The HTTP status.
///   - headers: Response header fields.
///   - sourceLocation: Where the mock was written, so a failure names that line.
/// - Returns: The response, or an inert `500` once the failure has been recorded.
func testHTTPResponse(
    url: URL,
    statusCode: Int = 200,
    headers: [String: String]? = nil,
    sourceLocation: SourceLocation = #_sourceLocation
) -> HTTPURLResponse {
    guard let response = HTTPURLResponse(
        url: url, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: headers)
    else {
        Issue.record("Could not build an HTTPURLResponse for \(url)", sourceLocation: sourceLocation)
        // Unreachable in practice — the initializer fails only on a malformed version string,
        // which is a literal above. Recorded rather than trapped so one bad mock fails one test.
        return HTTPURLResponse()
    }
    return response
}

/// The URL a request is for.
///
/// `URLRequest.url` is optional because a request can be built without one. A request a mock
/// handler has been handed always has one, and the alternative to this is `request.url!` in
/// every handler.
///
/// - Parameters:
///   - request: The request being answered.
///   - sourceLocation: Where the handler was written, so a failure names that line.
/// - Returns: The request's URL, or an inert sentinel once the failure has been recorded.
func testRequestURL(
    _ request: URLRequest, sourceLocation: SourceLocation = #_sourceLocation
) -> URL {
    guard let url = request.url else {
        Issue.record("A request reached a mock handler with no URL", sourceLocation: sourceLocation)
        return URL(string: "about:blank") ?? URL(fileURLWithPath: "/")
    }
    return url
}

/// A JSON body a test builds from a dictionary of literals.
///
/// `JSONSerialization.data(withJSONObject:)` throws on a value it cannot represent. Every caller
/// here passes a dictionary written out in the test, so the throw is unreachable — but `try!`
/// makes that unreachability load-bearing, and takes the whole run down if a future edit puts a
/// non-JSON value in the literal. This names the offending body instead.
///
/// - Parameters:
///   - object: The JSON object to encode.
///   - sourceLocation: Where the body was written, so a failure names that line.
/// - Returns: The encoded body, or empty data once the failure has been recorded.
func testJSONBody(
    _ object: [String: Any], sourceLocation: SourceLocation = #_sourceLocation
) -> Data {
    do {
        return try JSONSerialization.data(withJSONObject: object)
    } catch {
        Issue.record("Not a JSON-representable body: \(error)", sourceLocation: sourceLocation)
        return Data()
    }
}

// MARK: - Floating-point claims

/// Whether two `Double`s are the same value, bit for bit.
///
/// `==` on floating point hides three different claims: *these were computed the same way*,
/// *these are close enough for the purpose*, and *this value came through unchanged*. Only the
/// third one is ever meant when a test round-trips a literal through a wrapper, an encoder or a
/// transport, and it is stronger than any tolerance — a tolerance would pass on a value that had
/// been quietly rounded.
///
/// Comparing bit patterns says exactly that. It also makes the two `NaN` and `±0` cases
/// deliberate rather than accidental: `NaN` matches itself here and `-0` does not match `+0`,
/// which is what "came through unchanged" means.
///
/// - Parameters:
///   - actual: The value under test.
///   - expected: The value it should still be.
/// - Returns: `true` when the two are bitwise identical.
func isBitIdentical(_ actual: Double, _ expected: Double) -> Bool {
    actual.bitPattern == expected.bitPattern
}

/// Whether two `Double`s agree to within `tolerance`.
///
/// The other claim `==` hides — *close enough* — said where it is actually the claim, which is
/// after arithmetic rather than after carriage.
///
/// - Parameters:
///   - actual: The computed value.
///   - expected: The value it should approximate.
///   - tolerance: The largest difference that still counts as agreement.
/// - Returns: `true` when the difference is within `tolerance`.
func isApproximately(_ actual: Double, _ expected: Double, within tolerance: Double) -> Bool {
    abs(actual - expected) <= tolerance
}

/// Whether an optional `Double` is present and the same value, bit for bit.
///
/// `optional == literal` is `false` for `nil`, so this overload carries the same meaning while
/// keeping the two claims — *present* and *unchanged* — visible.
///
/// - Parameters:
///   - actual: The value under test, which may be absent.
///   - expected: The value it should still be.
/// - Returns: `true` when the value is present and bitwise identical.
func isBitIdentical(_ actual: Double?, _ expected: Double) -> Bool {
    guard let actual else { return false }
    return actual.bitPattern == expected.bitPattern
}

/// A price formatted to two decimal places.
///
/// `String(format: "%.2f", …)` bridges to the C `printf` ABI, where the format string and the
/// argument types are checked by nothing — a mismatch is undefined behaviour rather than a
/// compile error. `FormatStyle` knows the type it is formatting.
///
/// - Parameter amount: The amount to render.
/// - Returns: The amount with exactly two fractional digits.
func currency(_ amount: Double) -> String {
    amount.formatted(.number.precision(.fractionLength(2)).grouping(.never))
}
