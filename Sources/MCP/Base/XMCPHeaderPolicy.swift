import Foundation

/// Why an `x-mcp-header` annotation was refused.
public enum XMCPHeaderError: Error, Hashable, Sendable {
    /// The header name was empty, held a control character, or was not an HTTP field-name token.
    case invalidHeaderName(String)
    /// Two annotations resolved to the same header name, compared case-insensitively.
    case duplicateHeaderName(String)
    /// The annotated property was not `integer`, `string` or `boolean`.
    case unsupportedPropertyType(property: String, type: String)
    /// The annotation sat somewhere not statically reachable from the schema root.
    case notStaticallyReachable(keyword: String)
}

/// One tool excluded from a listing, and why.
public struct XMCPHeaderRejection: Hashable, Sendable {
    /// The name of the tool that was excluded.
    public let tool: String
    /// The reason it was excluded.
    public let reason: XMCPHeaderError
}

/// Validity rules for the `x-mcp-header` annotation, from MCP `2026-07-28`.
///
/// A server may annotate a tool property so a client mirrors that argument into an
/// `Mcp-Param-{Name}` header, letting intermediaries route without parsing the body. A client
/// **MUST reject** a tool definition that violates any constraint — by excluding that tool from
/// `tools/list` rather than failing the listing, so one malformed definition cannot deny every
/// other tool. ``filtering(_:)`` does exactly that.
public enum XMCPHeaderPolicy {
    /// The annotation keyword.
    public static let annotation = "x-mcp-header"

    /// Characters permitted in an HTTP field name (`tchar`, RFC 9110 §5.1).
    private static let tchar = Set(
        "!#$%&'*+-.^_`|~0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")

    /// The types an annotated property may declare.
    ///
    /// `number` is excluded by name: a float has no single canonical spelling as a header value,
    /// so a server could not reliably compare the header against the body.
    private static let allowedTypes: Set<String> = ["integer", "string", "boolean"]

    /// Collects the header names an input schema declares, checking every constraint.
    ///
    /// - Parameter inputSchema: The tool's `inputSchema`.
    /// - Returns: A map of dotted property path to header name.
    /// - Throws: ``XMCPHeaderError`` when any annotation is invalid.
    public static func headerNames(in inputSchema: Value) throws -> [String: String] {
        var found: [String: String] = [:]
        var seenLowercased: Set<String> = []

        try reachable(inputSchema, path: [], found: &found, seen: &seenLowercased)
        try refuseUnreachableAnnotations(inputSchema)
        return found
    }

    /// Walks the statically reachable properties — those reached through `properties` keys only.
    private static func reachable(
        _ node: Value,
        path: [String],
        found: inout [String: String],
        seen: inout Set<String>
    ) throws {
        guard case .object(let fields) = node,
            case .object(let properties)? = fields["properties"]
        else { return }

        for (name, property) in properties {
            guard case .object(let propertyFields) = property else { continue }
            let propertyPath = path + [name]

            if let header = propertyFields[annotation]?.stringValue {
                guard isValidHeaderName(header) else {
                    throw XMCPHeaderError.invalidHeaderName(header)
                }
                guard seen.insert(header.lowercased()).inserted else {
                    throw XMCPHeaderError.duplicateHeaderName(header)
                }
                let type = propertyFields["type"]?.stringValue ?? "unknown"
                guard allowedTypes.contains(type) else {
                    throw XMCPHeaderError.unsupportedPropertyType(
                        property: propertyPath.joined(separator: "."), type: type)
                }
                found[propertyPath.joined(separator: ".")] = header
            }

            try reachable(property, path: propertyPath, found: &found, seen: &seen)
        }
    }

    /// Refuses an annotation sitting anywhere a client could not find it before the call.
    ///
    /// The chain from the root must consist solely of `properties` keys. An annotation under
    /// `items`, a composition keyword, a conditional, or behind a `$ref` is invalid — not
    /// ignored — because the client cannot know which header to send until it has the arguments,
    /// by which point the routing decision the header exists for has already been made.
    private static func refuseUnreachableAnnotations(_ node: Value) throws {
        let disqualifying = ["items", "oneOf", "anyOf", "allOf", "not", "if", "then", "else", "$ref"]

        func scan(_ node: Value, underDisqualifying keyword: String?) throws {
            switch node {
            case .array(let elements):
                for element in elements { try scan(element, underDisqualifying: keyword) }
            case .object(let fields):
                if keyword != nil, fields[annotation] != nil {
                    throw XMCPHeaderError.notStaticallyReachable(keyword: keyword ?? "")
                }
                for (key, value) in fields {
                    let nowUnder = keyword ?? (disqualifying.contains(key) ? key : nil)
                    try scan(value, underDisqualifying: nowUnder)
                }
            default:
                break
            }
        }
        try scan(node, underDisqualifying: nil)
    }

    /// Whether a header name is a non-empty HTTP field-name token.
    private static func isValidHeaderName(_ name: String) -> Bool {
        !name.isEmpty && name.allSatisfy { tchar.contains($0) }
    }

    /// Splits a tool list into the tools a client may use and those it must exclude.
    ///
    /// Rejecting one tool must not deny the others, so this returns both halves rather than
    /// throwing. Callers should log each rejection with the tool name and reason.
    ///
    /// - Parameter tools: The tools as the server listed them.
    /// - Returns: The usable tools, and the rejections.
    public static func filtering(_ tools: [Tool]) -> (kept: [Tool], rejected: [XMCPHeaderRejection]) {
        var kept: [Tool] = []
        var rejected: [XMCPHeaderRejection] = []
        for tool in tools {
            do {
                _ = try headerNames(in: tool.inputSchema)
                kept.append(tool)
            } catch let error as XMCPHeaderError {
                rejected.append(XMCPHeaderRejection(tool: tool.name, reason: error))
            } catch {
                rejected.append(
                    XMCPHeaderRejection(tool: tool.name, reason: .invalidHeaderName("unknown")))
            }
        }
        return (kept, rejected)
    }
}
