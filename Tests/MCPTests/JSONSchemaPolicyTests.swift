import Foundation
import Testing

@testable import MCP

/// The `$ref` resolution and composition-keyword bounds MCP `2026-07-28` requires of anything
/// validating a tool's `inputSchema` or `outputSchema`.
///
/// The headline rule is a refusal, not a capability: implementations **MUST NOT** automatically
/// dereference a `$ref` that resolves to a network URI. Fetching may be offered as opt-in, but
/// it must be off by default — a schema is attacker-controlled input, and a validator that
/// fetches on sight is an SSRF gadget that runs on every `tools/list`.
@Suite("JSON Schema Policy")
struct JSONSchemaPolicyTests {

    @Test("A local reference resolves")
    func testLocalReferenceResolves() throws {
        let schema: Value = .object([
            "type": .string("object"),
            "properties": .object(["a": .object(["$ref": .string("#/$defs/thing")])]),
            "$defs": .object(["thing": .object(["type": .string("string")])]),
        ])
        try JSONSchemaPolicy.validate(schema)
    }

    /// The rule that matters most: a network `$ref` is refused rather than fetched.
    @Test("A network reference is refused, not fetched", arguments: [
        "https://evil.example.com/schema.json",
        "http://example.com/schema.json",
        "https://example.com/s.json#/$defs/x",
    ])
    func testNetworkReferenceRefused(reference: String) throws {
        let schema: Value = .object([
            "type": .string("object"),
            "properties": .object(["a": .object(["$ref": .string(reference)])]),
        ])
        #expect(throws: JSONSchemaError.self) { try JSONSchemaPolicy.validate(schema) }
    }

    /// A schema whose reference cannot be resolved is rejected rather than treated as
    /// permissive — otherwise an unresolvable ref silently becomes "accept anything".
    @Test("An unresolvable local reference is rejected, not treated as permissive")
    func testUnresolvableReferenceRejected() throws {
        let schema: Value = .object([
            "type": .string("object"),
            "properties": .object(["a": .object(["$ref": .string("#/$defs/missing")])]),
            "$defs": .object(["other": .object(["type": .string("string")])]),
        ])
        #expect(throws: JSONSchemaError.self) { try JSONSchemaPolicy.validate(schema) }
    }

    /// A reference cycle must terminate. Without detection this is an infinite loop reachable
    /// from any published tool definition.
    @Test("A reference cycle is detected rather than followed")
    func testReferenceCycleDetected() throws {
        let schema: Value = .object([
            "type": .string("object"),
            "$defs": .object([
                "a": .object(["$ref": .string("#/$defs/b")]),
                "b": .object(["$ref": .string("#/$defs/a")]),
            ]),
            "properties": .object(["x": .object(["$ref": .string("#/$defs/a")])]),
        ])
        #expect(throws: JSONSchemaError.self) { try JSONSchemaPolicy.validate(schema) }
    }

    /// Depth is bounded. A deeply nested schema is cheap to publish and expensive to validate.
    @Test("An over-deep schema is rejected")
    func testDepthBounded() throws {
        var nested: Value = .object(["type": .string("string")])
        for _ in 0..<(JSONSchemaPolicy.maximumDepth + 5) {
            nested = .object(["type": .string("object"), "properties": .object(["n": nested])])
        }
        #expect(throws: JSONSchemaError.self) { try JSONSchemaPolicy.validate(nested) }
    }

    /// The count of subschemas is bounded too: breadth is as cheap to publish as depth.
    @Test("A schema with too many subschemas is rejected")
    func testSubschemaCountBounded() throws {
        var branches: [Value] = []
        for index in 0...(JSONSchemaPolicy.maximumSubschemas + 1) {
            branches.append(.object(["const": .int(index)]))
        }
        let schema: Value = .object([
            "type": .string("object"),
            "anyOf": .array(branches),
        ])
        #expect(throws: JSONSchemaError.self) { try JSONSchemaPolicy.validate(schema) }
    }

    /// Composition keywords are permitted — the revision explicitly allows them. Only their
    /// unbounded use is refused.
    @Test("Composition keywords within bounds are accepted")
    func testCompositionWithinBoundsAccepted() throws {
        let schema: Value = .object([
            "type": .string("object"),
            "properties": .object([
                "a": .object([
                    "oneOf": .array([
                        .object(["type": .string("string")]),
                        .object(["type": .string("integer")]),
                    ])
                ])
            ]),
            "if": .object(["required": .array([.string("a")])]),
            "then": .object(["required": .array([.string("a")])]),
        ])
        try JSONSchemaPolicy.validate(schema)
    }
}
