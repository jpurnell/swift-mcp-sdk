import Foundation
import Testing

@testable import MCP

/// `x-mcp-header` validity, from MCP `2026-07-28`.
///
/// A server may annotate a tool property so clients mirror that argument into an
/// `Mcp-Param-{Name}` header. A client **MUST reject** a tool definition violating any
/// constraint — by excluding that tool from `tools/list`, not by failing the whole listing, so
/// one malformed definition cannot deny every other tool.
@Suite("x-mcp-header Policy")
struct XMCPHeaderPolicyTests {

    private func schema(_ properties: [String: Value], extra: [String: Value] = [:]) -> Value {
        var fields: [String: Value] = [
            "type": .string("object"),
            "properties": .object(properties),
        ]
        for (key, value) in extra { fields[key] = value }
        return .object(fields)
    }

    @Test("A conforming annotation is accepted and its header name returned")
    func testConformingAnnotation() throws {
        let input = schema([
            "region": .object(["type": .string("string"), "x-mcp-header": .string("Region")]),
            "query": .object(["type": .string("string")]),
        ])
        let headers = try XMCPHeaderPolicy.headerNames(in: input)
        #expect(headers == ["region": "Region"])
    }

    @Test("An empty or non-token header name is rejected", arguments: ["", "Bad Header", "Bad:Header", "Bad\r\nInject"])
    func testInvalidTokenRejected(name: String) throws {
        let input = schema(["a": .object(["type": .string("string"), "x-mcp-header": .string(name)])])
        #expect(throws: XMCPHeaderError.self) { _ = try XMCPHeaderPolicy.headerNames(in: input) }
    }

    /// Uniqueness is case-insensitive: two annotations differing only in case would produce one
    /// header, and the server could not tell which argument it came from.
    @Test("Case-insensitively duplicate header names are rejected")
    func testDuplicateNamesRejected() throws {
        let input = schema([
            "a": .object(["type": .string("string"), "x-mcp-header": .string("Region")]),
            "b": .object(["type": .string("string"), "x-mcp-header": .string("region")]),
        ])
        #expect(throws: XMCPHeaderError.self) { _ = try XMCPHeaderPolicy.headerNames(in: input) }
    }

    /// `number` is excluded by name: a float has no single canonical header spelling, so the
    /// server's comparison against the body could not be made reliable.
    @Test("Only primitive types are allowed, and number is excluded", arguments: [
        "number", "object", "array", "null",
    ])
    func testDisallowedTypesRejected(type: String) throws {
        let input = schema(["a": .object(["type": .string(type), "x-mcp-header": .string("A")])])
        #expect(throws: XMCPHeaderError.self) { _ = try XMCPHeaderPolicy.headerNames(in: input) }
    }

    @Test("Integer, string and boolean are allowed", arguments: ["integer", "string", "boolean"])
    func testAllowedTypesAccepted(type: String) throws {
        let input = schema(["a": .object(["type": .string(type), "x-mcp-header": .string("A")])])
        let headers = try XMCPHeaderPolicy.headerNames(in: input)
        #expect(headers == ["a": "A"])
    }

    /// Static reachability: the annotation must sit on a property reachable through `properties`
    /// keys alone. Anywhere else the client cannot know, before the call, which header to send.
    @Test("An annotation reached through a non-properties keyword is rejected", arguments: [
        "items", "oneOf", "anyOf", "allOf", "not", "if", "then", "else",
    ])
    func testUnreachableAnnotationRejected(keyword: String) throws {
        let annotated: Value = .object([
            "type": .string("object"),
            "properties": .object([
                "inner": .object(["type": .string("string"), "x-mcp-header": .string("Inner")])
            ]),
        ])
        let wrapped: Value =
            ["oneOf", "anyOf", "allOf"].contains(keyword)
            ? .array([annotated]) : annotated

        let input = schema(["a": .object(["type": .string("object")])], extra: [keyword: wrapped])
        #expect(
            throws: XMCPHeaderError.self,
            "an annotation under '\(keyword)' is not statically reachable"
        ) { _ = try XMCPHeaderPolicy.headerNames(in: input) }
    }

    /// Nested objects are fine, as long as every step is a `properties` key.
    @Test("A nested annotation reached only through properties is accepted")
    func testNestedPropertiesAccepted() throws {
        let input = schema([
            "outer": .object([
                "type": .string("object"),
                "properties": .object([
                    "region": .object([
                        "type": .string("string"), "x-mcp-header": .string("Region"),
                    ])
                ]),
            ])
        ])
        let headers = try XMCPHeaderPolicy.headerNames(in: input)
        #expect(headers == ["outer.region": "Region"])
    }

    /// One malformed tool must not deny the others — the client excludes it and keeps the rest.
    @Test("Filtering drops only the offending tool")
    func testFilteringDropsOnlyTheOffender() throws {
        let good = Tool(
            name: "good", description: "fine",
            inputSchema: schema(["a": .object(["type": .string("string"), "x-mcp-header": .string("A")])]))
        let bad = Tool(
            name: "bad", description: "malformed",
            inputSchema: schema(["a": .object(["type": .string("number"), "x-mcp-header": .string("A")])]))

        let (kept, rejected) = XMCPHeaderPolicy.filtering([good, bad])
        #expect(kept.map(\.name) == ["good"])
        #expect(rejected.count == 1)
        #expect(rejected.first?.tool == "bad")
    }
}
