# 2026-10-25 — quality-gate cleanup

**Branch:** `integration/mcp-2026-07-28`

## What was wrong
Gate: 23 errors, 528 warnings — doc-comment examples that did not compile (20), an unguarded
`Int(Double)` conversion, ~300 undocumented public declarations, silent `try?`/empty `catch`,
UUIDs used as session/state capabilities, an unchecked SSRF target in the conformance client,
`http://` and credential-named identifiers in tests, a Sendable-metatype capture, a wall-clock
assertion, an unreachable helper, and a branch-pinned dependency.

## What changed (no overrides, suppressions or config exclusions)
Five parallel worktrees (server, client, base/transports, authorization, tests/conformance),
merged into the integration branch. See the CHANGELOG entry "quality-gate cleanup".

## Verification
`swift test`: 669 tests / 57 suites pass on the merged tree.

## Known remaining / watch
- `stochastic-determinism` on `PKCE.swift` (`SecureRandomNumberGenerator`, the one place naming the system generator). A `getentropy` replacement was tried and rejected by pointer-escape + build portability.
- `testReconnectionBackoff` now checks the backoff schedule, not that the transport waits.
- Conformance client: an IdP on a different non-loopback host with no `idp_issuer` now fails.
- swift-log has no `privacy:` parameter; values are logged as metadata.
