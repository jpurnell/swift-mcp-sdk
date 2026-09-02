# ``MCP``

A Swift implementation of the Model Context Protocol, serving revision `2026-07-28` alongside
the revisions before it.

## Overview

This is a **fork** of [modelcontextprotocol/swift-sdk][upstream], carrying the `2026-07-28` work
upstream does not yet have. It is not the official SDK.

The module provides both halves of the protocol:

- ``Client`` — connects to a server, calls its tools, reads its resources, and answers the
  sampling, elicitation and roots requests a server may make of it.
- ``Server`` — registers handlers by method type and answers whichever transport it is given.

Transports are interchangeable: ``StdioTransport`` for a subprocess, ``HTTPClientTransport`` and
the Streamable HTTP server transports for a network peer, ``InMemoryTransport`` for a test.

### What `2026-07-28` changed

The revision removes the `initialize` handshake. A request instead declares its own protocol
version and client capabilities in `_meta`, so any instance can answer any request without a
sticky session — which is what ``Discover`` and ``Metadata/protocolVersion`` exist for. The
standalone `GET` stream is replaced by ``SubscriptionsListen``, and results carry a
``ResultType`` saying how to read them.

Both revisions are served from one implementation. A client that sends none of this is on an
earlier revision and is answered by that revision's rules.

## Topics

### Connecting

- ``Client``
- ``Server``
- ``Transport``

### Transports

- ``StdioTransport``
- ``HTTPClientTransport``
- ``InMemoryTransport``
- ``NetworkTransport``

### The protocol surface

- ``Tool``
- ``Resource``
- ``Prompt``
- ``Sampling``
- ``Discover``
- ``SubscriptionsListen``

### Per-request carriage

- ``Metadata``
- ``ResultType``
- ``Value``

### Errors

- ``MCPError``

[upstream]: https://github.com/modelcontextprotocol/swift-sdk
