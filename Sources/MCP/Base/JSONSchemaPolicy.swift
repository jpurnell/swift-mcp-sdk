import Foundation

/// Why a schema was refused.
public enum JSONSchemaError: Error, Hashable, Sendable {
    /// A `$ref` pointed at a network URI. These are never dereferenced automatically.
    case networkReferenceNotAllowed(String)
    /// A local `$ref` pointed at something the schema does not define.
    case unresolvableReference(String)
    /// Following `$ref`s returned to a schema already being resolved.
    case referenceCycle(String)
    /// The schema nested deeper than ``JSONSchemaPolicy/maximumDepth``.
    case tooDeep(limit: Int)
    /// The schema held more subschemas than ``JSONSchemaPolicy/maximumSubschemas``.
    case tooManySubschemas(limit: Int)
}

/// The `$ref` and resource rules MCP `2026-07-28` requires of anything validating a tool's
/// `inputSchema` or `outputSchema`.
///
/// ## The headline rule is a refusal
///
/// Implementations **MUST NOT** automatically dereference a `$ref` that resolves to a network
/// URI. Fetching may be offered, but it must be **off by default**, and this type does not offer
/// it at all. A tool schema is attacker-controlled input that a client validates on every
/// `tools/list`, so a validator that fetches on sight is a server-side request forgery gadget
/// triggered by merely listing tools.
///
/// A schema that cannot be validated because a reference is unresolved is **rejected**, never
/// treated as permissive. Silently accepting it would turn a broken reference into "accept
/// anything", which is the opposite of what a schema is for.
///
/// ## Bounds
///
/// Composition keywords (`anyOf`, `oneOf`, `allOf`, `if`/`then`/`else`) and `$defs` are allowed
/// — the revision explicitly permits them — but their unbounded use is not. Depth and subschema
/// count are capped, because both are cheap to publish and expensive to validate, and a cycle
/// terminates rather than looping.
public enum JSONSchemaPolicy {
    /// The deepest a schema may nest.
    public static let maximumDepth = 32
    /// The most subschemas a single schema may contain.
    public static let maximumSubschemas = 1000

    /// Checks a schema against the policy.
    ///
    /// - Parameter schema: The schema to check, as decoded JSON.
    /// - Throws: ``JSONSchemaError`` when the schema violates the policy.
    public static func validate(_ schema: Value) throws {
        var counter = 0
        try walk(schema, root: schema, depth: 0, resolving: [], counter: &counter)
    }

    private static func walk(
        _ node: Value,
        root: Value,
        depth: Int,
        resolving: Set<String>,
        counter: inout Int
    ) throws {
        guard depth <= maximumDepth else { throw JSONSchemaError.tooDeep(limit: maximumDepth) }

        switch node {
        case .array(let elements):
            for element in elements {
                try walk(element, root: root, depth: depth + 1, resolving: resolving, counter: &counter)
            }

        case .object(let fields):
            counter += 1
            guard counter <= maximumSubschemas else {
                throw JSONSchemaError.tooManySubschemas(limit: maximumSubschemas)
            }

            if let reference = fields["$ref"]?.stringValue {
                try follow(reference, root: root, depth: depth, resolving: resolving, counter: &counter)
            }

            for (key, value) in fields where key != "$ref" {
                try walk(value, root: root, depth: depth + 1, resolving: resolving, counter: &counter)
            }

        default:
            break
        }
    }

    /// Resolves one `$ref`, refusing anything that is not a local JSON Pointer.
    private static func follow(
        _ reference: String,
        root: Value,
        depth: Int,
        resolving: Set<String>,
        counter: inout Int
    ) throws {
        // Only a same-document pointer is ever followed. Anything with a scheme or authority is
        // a network reference, and those are refused rather than fetched.
        guard reference.hasPrefix("#") else {
            throw JSONSchemaError.networkReferenceNotAllowed(reference)
        }
        guard !resolving.contains(reference) else {
            throw JSONSchemaError.referenceCycle(reference)
        }
        guard let target = pointer(reference, in: root) else {
            throw JSONSchemaError.unresolvableReference(reference)
        }
        try walk(
            target, root: root, depth: depth + 1,
            resolving: resolving.union([reference]), counter: &counter)
    }

    /// Resolves a same-document JSON Pointer such as `#/$defs/thing`.
    private static func pointer(_ reference: String, in root: Value) -> Value? {
        let path = reference.dropFirst()  // leading '#'
        guard !path.isEmpty else { return root }
        guard path.hasPrefix("/") else { return nil }  // $anchor form, not a pointer

        var node = root
        for rawSegment in path.dropFirst().split(separator: "/", omittingEmptySubsequences: false) {
            // JSON Pointer escapes: ~1 is '/', ~0 is '~', in that order.
            let segment = rawSegment
                .replacingOccurrences(of: "~1", with: "/")
                .replacingOccurrences(of: "~0", with: "~")
            guard case .object(let fields) = node, let next = fields[segment] else { return nil }
            node = next
        }
        return node
    }
}
