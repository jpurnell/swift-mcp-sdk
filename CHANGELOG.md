# Changelog

This is a **fork** of [modelcontextprotocol/swift-sdk][upstream], carrying MCP `2026-07-28`
support that upstream does not yet have. It is not the official SDK, and this file records what
the fork adds rather than restating upstream's history.

The fork's name, published version and attribution are still undecided — see
`SwiftMCPServer/project/plans/proposals/UpstreamingToSwiftSDK.md` §5. Until that is settled,
nothing here is tagged, and consumers reach it by path.

## [Unreleased] — `integration/mcp-2026-07-28`

### Added — MCP `2026-07-28`

- **`server/discover`** and per-request protocol carriage in `_meta` (SEP-2575), the pair that
  removes the `initialize` handshake and lets any instance answer any request.
- **`subscriptions/listen`** (SEP-2575), replacing the standalone GET stream.
- **Multi Round-Trip Requests** and the MRTR result union (SEP-2322), with `resultType` tagging
  on every result.
- **The `io.modelcontextprotocol/tasks` extension** (SEP-2663).
- **`x-mcp-header` validity rules** (SEP-2243) and JSON Schema `$ref` policy with composition
  bounds (SEP-2106).
- **Cacheable list and read results** (SEP-2549) — `ttlMs` and `cacheScope`.
- **Protocol errors and the 2026-07-28 code allocation policy** (SEP-2575): `-32020`
  HeaderMismatch, `-32021` MissingRequiredClientCapability, `-32022`
  UnsupportedProtocolVersion, with `urlElicitationRequired` moved out of the range the
  specification reserved for itself.
- **`MCPError.structured(code:message:data:)`** — errors carrying the payload their code is
  defined by, rather than a detail string a receiver would have to parse back. Factories for the
  three the specification defines: `missingRequiredClientCapability(requiring:)`,
  `resourceNotFound(uri:)`, `unsupportedProtocolVersion(requested:supported:)`.
- **Responses identify the server** in `_meta["io.modelcontextprotocol/serverInfo"]` (spec PR
  #3002). A client on this revision never sees an `initialize` result, so a response is the only
  place it can learn which instance answered.
- **Decode conformance against the specification's own examples** — all 129, across 91
  definitions. Only `2026-07-28` and `draft` ship examples, so these were authored for this
  revision rather than inherited.

### Fixed

- **`NetworkTransport`'s heartbeat is little-endian by specification, not by accident.** It read
  its timestamp with `load(as: UInt64.self)` on a `Data` slice — which requires alignment the
  slice does not guarantee — and wrote it by dumping host memory, taking the machine's byte
  order for a wire format's. Both ends now shift bytes explicitly. Little-endian is what every
  platform this has run on already produced, so nothing on the wire changes.
- **`Client.Batch` holds its client weakly.** `addRequest` registers its pending request from a
  detached `Task` that can outlive the `withBatch` scope; `unowned` turned a client released in
  that window into a crash, and the same window now resumes the caller with `connectionClosed`.
- **The authorization retry loop is bounded where it is written.** `while true` with a
  `continue` guard fifty lines below reads as unbounded, and one edit to that branch would make
  it so.
- **`-32020`, `-32021` and `-32022` decode into their own cases** rather than falling through to
  `.serverError`, which is the catch-all for codes the SDK does not know.

### Changed — quality gate

The fork is held to this project's quality gate, which upstream's code was not written against.

- **581 force unwraps in the test suite became total forms.** `Data(s.utf8)` and
  `String(decoding:as:)` cannot fail at all; the rest are literals written by a test's author,
  where `testURL` / `testHTTPResponse` / `testJSONBody` record a failure naming the bad literal
  instead of trapping and taking the run down with them.
- **Exact `==` on floating point says which claim it makes.** `isBitIdentical` for a value that
  came through unchanged, `isApproximately(_:_:within:)` for one that was computed.
- **Every `@unchecked Sendable` and `nonisolated(unsafe)` states what serialises it.**
- **Pointer use inside `withUnsafe*` blocks no longer constructs a second pointer to the same
  memory**, which is the shape that goes wrong when someone later returns it.

[upstream]: https://github.com/modelcontextprotocol/swift-sdk
