import Foundation

#if canImport(System)
    import System
#else
    @preconcurrency import SystemPackage
#endif

/// Information about a required URL elicitation
public struct URLElicitationInfo: Codable, Hashable, Sendable {
    /// Elicitation mode (must be "url")
    public var mode: String
    /// Unique identifier for this elicitation
    public var elicitationId: String
    /// URL for the user to visit
    public var url: String
    /// Message describing the elicitation
    public var message: String

    public init(mode: String = "url", elicitationId: String, url: String, message: String) {
        self.mode = mode
        self.elicitationId = elicitationId
        self.url = url
        self.message = message
    }
}

/// A model context protocol error.
public enum MCPError: Swift.Error, Sendable {
    // Standard JSON-RPC 2.0 errors (-32700 to -32603)
    case parseError(String?)  // -32700
    case invalidRequest(String?)  // -32600
    case methodNotFound(String?)  // -32601
    case invalidParams(String?)  // -32602
    case internalError(String?)  // -32603

    // Protocol errors reserved by the specification (-32020 to -32099).
    //
    // MCP 2026-07-28 partitions the JSON-RPC server-error range: -32000 to -32019 stays
    // implementation-defined, with existing usage grandfathered, and -32020 onwards belongs to
    // the specification. These three were renumbered into that range by SEP-2575.
    /// A resource was requested that the server does not have.
    ///
    /// MCP 2026-07-28 moved this from -32002 to -32602, aligning it with JSON-RPC's invalid
    /// params. The old code is NOT decoded back into this case: -32002 is also this SDK's
    /// request-cancelled code, so a receiver cannot tell the two apart, and guessing would
    /// mistranslate one of them.
    case resourceNotFound(String?)  // -32602

    /// A required MCP request header was missing or disagreed with the request body.
    case headerMismatch(String?)  // -32020
    /// The request needed a client capability the client did not declare.
    case missingRequiredClientCapability(String?)  // -32021
    /// The client asked for a protocol version this server does not support.
    case unsupportedProtocolVersion(String?)  // -32022

    /// An error whose `data` carries the structured payload the specification defines for its
    /// code.
    ///
    /// Several errors are only actionable through `data`: the capabilities a request needed
    /// (`-32021`), the URI that was refused (`-32602`), the versions a server will serve
    /// (`-32022`). Every other case here carries a free-text detail, which cannot express any of
    /// those without inventing a string format the receiver would have to parse back.
    ///
    /// Build one through ``missingRequiredClientCapability(requiring:)``,
    /// ``resourceNotFound(uri:)`` or ``unsupportedProtocolVersion(requested:supported:)`` rather
    /// than by hand. Those share a name with the free-text cases above and differ in their
    /// argument labels — the same error, said with a payload instead of a sentence — so match on
    /// ``code`` rather than on the case when either form may arrive.
    case structured(code: Int, message: String, data: [String: Value])

    // Server errors (-32000 to -32099)
    case serverError(code: Int, message: String)

    // MCP specific errors
    case urlElicitationRequired(message: String, elicitations: [URLElicitationInfo])  // -32003

    // Transport specific errors
    case connectionClosed
    case transportError(Swift.Error)

    /// The JSON-RPC 2.0 error code
    public var code: Int {
        switch self {
        case .parseError: return -32700
        case .invalidRequest: return -32600
        case .methodNotFound: return -32601
        case .invalidParams: return -32602
        case .internalError: return -32603
        case .resourceNotFound: return -32602
        case .headerMismatch: return -32020
        case .missingRequiredClientCapability: return -32021
        case .unsupportedProtocolVersion: return -32022
        case .structured(let code, _, _): return code
        case .serverError(let code, _): return code
        // Renumbered from -32042 by the 2026-07-28 allocation policy: that code sits inside
        // the range the specification reserves for itself, and the revision removed the
        // URLElicitationRequiredError definition entirely. URL-mode elicitation still exists,
        // so the case is kept and moved into the implementation-defined range rather than
        // deleted. This changes the wire code for any consumer matching on -32042.
        //
        // -32003, not -32002: that code is already StatelessHTTPServerTransport's
        // request-cancelled code, AND it was the resource not-found code before this revision
        // moved that to -32602, so peers on earlier revisions still send it with the older
        // meaning. Two senders of one code cannot be told apart by the receiver.
        case .urlElicitationRequired: return -32003
        case .connectionClosed: return -32000
        case .transportError: return -32001
        }
    }

    /// The structured `data` payload this error carries, if it has one.
    ///
    /// `nil` for the free-text cases, whose `data` is a `detail` string rather than a shape the
    /// receiver can act on.
    public var structuredData: [String: Value]? {
        guard case .structured(_, _, let data) = self else { return nil }
        return data
    }

    /// A `-32021` naming the capabilities the request needed, as a `ClientCapabilities` object.
    ///
    /// The specification's own example carries `{"requiredCapabilities": {"elicitation": {}}}` —
    /// an object keyed by capability, not a list of names — so a client can merge the answer
    /// into what it already declares and retry. Each capability's value is an empty object
    /// because the client is being told *which* capability is missing, not how to configure it.
    ///
    /// - Parameter capabilities: The capability names the request could not proceed without.
    public static func missingRequiredClientCapability(requiring capabilities: [String]) -> MCPError {
        var required: [String: Value] = [:]
        for capability in capabilities { required[capability] = .object([:]) }
        let names = capabilities.joined(separator: ", ")
        return .structured(
            code: -32021,
            message: "Missing required client capability: \(names)",
            data: ["requiredCapabilities": .object(required)]
        )
    }

    /// A `-32602` naming the URI that was not found (SEP-2164).
    ///
    /// A client reading several resources at once cannot tell which read was refused from the
    /// message alone; the URI in `data` is what makes the error attributable.
    ///
    /// - Parameter uri: The resource URI the server does not have.
    public static func resourceNotFound(uri: String) -> MCPError {
        .structured(
            code: -32602,
            message: "Resource not found: \(uri)",
            data: ["uri": .string(uri)]
        )
    }

    /// A `-32022` carrying both the version that was asked for and the versions on offer.
    ///
    /// `supported` alone refuses the client without saying which of its attempts was refused,
    /// which matters when more than one is in flight. Echoing `requested` makes the error
    /// self-describing.
    ///
    /// - Parameters:
    ///   - requested: The protocol version the client asked for.
    ///   - supported: The versions this server will actually serve.
    public static func unsupportedProtocolVersion(
        requested: String, supported: [String]
    ) -> MCPError {
        .structured(
            code: -32022,
            message: "Unsupported protocol version '\(requested)'",
            data: [
                "requested": .string(requested),
                "supported": .array(supported.map { .string($0) }),
            ]
        )
    }

    /// Check if an error represents a "resource temporarily unavailable" condition
    public static func isResourceTemporarilyUnavailable(_ error: Swift.Error) -> Bool {
        #if canImport(System)
            if let errno = error as? System.Errno, errno == .resourceTemporarilyUnavailable {
                return true
            }
        #else
            if let errno = error as? SystemPackage.Errno, errno == .resourceTemporarilyUnavailable {
                return true
            }
        #endif
        return false
    }
}

// MARK: LocalizedError

extension MCPError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .parseError(let detail):
            return "Parse error: Invalid JSON" + (detail.map { ": \($0)" } ?? "")
        case .invalidRequest(let detail):
            return "Invalid Request" + (detail.map { ": \($0)" } ?? "")
        case .methodNotFound(let detail):
            return "Method not found" + (detail.map { ": \($0)" } ?? "")
        case .invalidParams(let detail):
            return "Invalid params" + (detail.map { ": \($0)" } ?? "")
        case .internalError(let detail):
            return "Internal error" + (detail.map { ": \($0)" } ?? "")
        case .resourceNotFound(let detail):
            return "Resource not found\(detail.map { ": \($0)" } ?? "")"
        case .headerMismatch(let detail):
            return "Header mismatch\(detail.map { ": \($0)" } ?? "")"
        case .missingRequiredClientCapability(let detail):
            return "Missing required client capability\(detail.map { ": \($0)" } ?? "")"
        case .unsupportedProtocolVersion(let detail):
            return "Unsupported protocol version\(detail.map { ": \($0)" } ?? "")"
        case .structured(_, let message, _):
            return message
        case .serverError(_, let message):
            return "Server error: \(message)"
        case .urlElicitationRequired(let message, _):
            return "URL elicitation required: \(message)"
        case .connectionClosed:
            return "Connection closed"
        case .transportError(let error):
            return "Transport error: \(error.localizedDescription)"
        }
    }

    public var failureReason: String? {
        switch self {
        case .parseError:
            return "The server received invalid JSON that could not be parsed"
        case .invalidRequest:
            return "The JSON sent is not a valid Request object"
        case .methodNotFound:
            return "The method does not exist or is not available"
        case .invalidParams:
            return "Invalid method parameter(s)"
        case .internalError:
            return "Internal JSON-RPC error"
        case .resourceNotFound:
            return "The requested resource does not exist on this server"
        case .headerMismatch:
            return "A required MCP request header was missing or disagreed with the request body"
        case .missingRequiredClientCapability:
            return "The request needed a client capability the client did not declare"
        case .unsupportedProtocolVersion:
            return "The requested protocol version is not supported by this server"
        case .structured:
            return "The error carries a structured payload describing what the request needed"
        case .serverError:
            return "Server-defined error occurred"
        case .urlElicitationRequired:
            return "The server requires user authentication or input via external URL"
        case .connectionClosed:
            return "The connection to the server was closed"
        case .transportError(let error):
            return (error as? LocalizedError)?.failureReason ?? error.localizedDescription
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .parseError:
            return "Verify that the JSON being sent is valid and well-formed"
        case .invalidRequest:
            return "Ensure the request follows the JSON-RPC 2.0 specification format"
        case .methodNotFound:
            return "Check the method name and ensure it is supported by the server"
        case .invalidParams:
            return "Verify the parameters match the method's expected parameters"
        case .urlElicitationRequired(_, let elicitations):
            if let first = elicitations.first {
                return "Visit \(first.url) to complete the required authentication or input"
            }
            return "Complete the required URL-based elicitation"
        case .connectionClosed:
            return "Try reconnecting to the server"
        default:
            return nil
        }
    }
}

// MARK: CustomDebugStringConvertible

extension MCPError: CustomDebugStringConvertible {
    public var debugDescription: String {
        switch self {
        case .transportError(let error):
            return
                "[\(code)] \(errorDescription ?? "") (Underlying error: \(String(reflecting: error)))"
        default:
            return "[\(code)] \(errorDescription ?? "")"
        }
    }

}

// MARK: Codable

extension MCPError: Codable {
    private enum CodingKeys: String, CodingKey {
        case code, message, data
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(code, forKey: .code)

        // Encode additional data if available
        switch self {
        case .parseError(let detail),
            .invalidRequest(let detail),
            .methodNotFound(let detail),
            .invalidParams(let detail),
            .internalError(let detail),
            .resourceNotFound(let detail),
            .headerMismatch(let detail),
            .missingRequiredClientCapability(let detail),
            .unsupportedProtocolVersion(let detail):
            try container.encode(errorDescription ?? "Unknown error", forKey: .message)
            if let detail = detail {
                try container.encode(["detail": detail], forKey: .data)
            }
        case .structured(_, let message, let data):
            try container.encode(message, forKey: .message)
            try container.encode(data, forKey: .data)
        case .serverError(_, _):
            // No additional data for server errors
            try container.encode(errorDescription ?? "Unknown error", forKey: .message)
            break
        case .urlElicitationRequired(let message, let elicitations):
            // Encode the raw message so decode can round-trip without prefix doubling
            try container.encode(message, forKey: .message)
            // Encode elicitations array as structured data
            let elicitationsData = elicitations.map { info -> [String: Value] in
                return [
                    "mode": .string(info.mode),
                    "elicitationId": .string(info.elicitationId),
                    "url": .string(info.url),
                    "message": .string(info.message)
                ]
            }
            try container.encode(
                ["elicitations": Value.array(elicitationsData.map { .object($0) })],
                forKey: .data
            )
        case .connectionClosed:
            try container.encode(errorDescription ?? "Unknown error", forKey: .message)
        case .transportError(let error):
            try container.encode(errorDescription ?? "Unknown error", forKey: .message)
            try container.encode(
                ["error": error.localizedDescription],
                forKey: .data
            )
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let code = try container.decode(Int.self, forKey: .code)
        let message = try container.decode(String.self, forKey: .message)
        let data = try container.decodeIfPresent([String: Value].self, forKey: .data)

        // Helper to extract detail from data, falling back to message if needed
        let unwrapDetail: (String?) -> String? = { fallback in
            guard let detailValue = data?["detail"] else { return fallback }
            if case .string(let str) = detailValue { return str }
            return fallback
        }

        // A payload the sender built to be acted on — anything beyond the free-text shapes this
        // type has always written — is kept whole. Flattening it into a detail string would
        // discard the only part a receiver can use, and it is the sender's own framing rather
        // than a guess about which case was meant.
        let freeTextKeys: Set<String> = ["detail", "error", "elicitations"]
        if let data, !data.isEmpty, !Set(data.keys).isSubset(of: freeTextKeys) {
            self = .structured(code: code, message: message, data: data)
            return
        }

        switch code {
        case -32700:
            self = .parseError(unwrapDetail(message))
        case -32600:
            self = .invalidRequest(unwrapDetail(message))
        case -32601:
            self = .methodNotFound(unwrapDetail(message))
        case -32602:
            self = .invalidParams(unwrapDetail(message))
        case -32603:
            self = .internalError(unwrapDetail(nil))
        // Accepts both codes on the way in. -32003 is what this SDK now emits; -32042 is what
        // it emitted before the 2026-07-28 allocation policy moved the case out of the
        // specification-reserved range, and a peer built against an older release still sends
        // it. Reading both costs one case and keeps those peers working.
        //
        // -32002 is deliberately NOT accepted here: it means request-cancelled to this SDK's
        // own stateless transport, and resource-not-found to any peer on a pre-2026 revision.
        // Decoding it as a URL elicitation would silently mistranslate both.
        case -32003, -32042:
            // Extract elicitations array from data
            var elicitations: [URLElicitationInfo] = []
            if case .array(let items) = data?["elicitations"] {
                for item in items {
                    if case .object(let dict) = item,
                       case .string(let mode) = dict["mode"],
                       case .string(let elicitationId) = dict["elicitationId"],
                       case .string(let url) = dict["url"],
                       case .string(let msg) = dict["message"] {
                        elicitations.append(URLElicitationInfo(
                            mode: mode,
                            elicitationId: elicitationId,
                            url: url,
                            message: msg))
                    }
                }
            }
            self = .urlElicitationRequired(message: message, elicitations: elicitations)
        // The three codes SEP-2575 moved into the reserved range. Without these they decoded as
        // `.serverError`, which is the catch-all for codes this SDK does not know — and these
        // are codes it does know.
        case -32020:
            self = .headerMismatch(unwrapDetail(message))
        case -32021:
            self = .missingRequiredClientCapability(unwrapDetail(message))
        case -32022:
            self = .unsupportedProtocolVersion(unwrapDetail(message))
        case -32000:
            self = .connectionClosed
        case -32001:
            // Extract underlying error string if present
            let underlyingErrorString =
                data?["error"].flatMap { val -> String? in
                    if case .string(let str) = val { return str }
                    return nil
                } ?? message
            self = .transportError(
                NSError(
                    domain: "org.jsonrpc.error",
                    code: code,
                    userInfo: [NSLocalizedDescriptionKey: underlyingErrorString]
                )
            )
        default:
            self = .serverError(code: code, message: message)
        }
    }
}

// MARK: Equatable

extension MCPError: Equatable {
    public static func == (lhs: MCPError, rhs: MCPError) -> Bool {
        switch (lhs, rhs) {
        case (.parseError(let a), .parseError(let b)): return a == b
        case (.invalidRequest(let a), .invalidRequest(let b)): return a == b
        case (.methodNotFound(let a), .methodNotFound(let b)): return a == b
        case (.invalidParams(let a), .invalidParams(let b)): return a == b
        case (.internalError(let a), .internalError(let b)): return a == b
        case (.structured(let c1, let m1, let d1), .structured(let c2, let m2, let d2)):
            return c1 == c2 && m1 == m2 && d1 == d2
        case (.serverError(let c1, let m1), .serverError(let c2, let m2)):
            return c1 == c2 && m1 == m2
        case (.urlElicitationRequired(let m1, let e1), .urlElicitationRequired(let m2, let e2)):
            return m1 == m2 && e1 == e2
        case (.connectionClosed, .connectionClosed): return true
        case (.transportError(let a), .transportError(let b)):
            return a.localizedDescription == b.localizedDescription
        default: return false
        }
    }
}

// MARK: Hashable

extension MCPError: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(code)
        switch self {
        case .parseError(let detail):
            hasher.combine(detail)
        case .invalidRequest(let detail):
            hasher.combine(detail)
        case .methodNotFound(let detail):
            hasher.combine(detail)
        case .invalidParams(let detail):
            hasher.combine(detail)
        case .internalError(let detail):
            hasher.combine(detail)
        case .resourceNotFound(let detail):
            hasher.combine(detail)
        case .headerMismatch(let detail):
            hasher.combine(detail)
        case .missingRequiredClientCapability(let detail):
            hasher.combine(detail)
        case .unsupportedProtocolVersion(let detail):
            hasher.combine(detail)
        case .structured(_, let message, let data):
            hasher.combine(message)
            hasher.combine(data)
        case .serverError(_, let message):
            hasher.combine(message)
        case .urlElicitationRequired(let message, let elicitations):
            hasher.combine(message)
            hasher.combine(elicitations)
        case .connectionClosed:
            break
        case .transportError(let error):
            hasher.combine(error.localizedDescription)
        }
    }
}
