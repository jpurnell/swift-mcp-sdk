import Foundation
import Testing

@testable import MCP

/// Records whether a server-side handler observed cancellation.
private actor CancellationObserver {
    private(set) var observed = false

    func mark() { observed = true }

    /// Polls until cancellation is observed or the timeout elapses.
    func waitForCancellation(timeout: Duration = .seconds(2)) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while !observed && ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        return observed
    }
}

@Suite("Cancellation Tests")
struct CancellationTests {
    @Test("Client sends CancelledNotification")
    func testClientSendsCancellation() async throws {
        let (clientTransport, serverTransport) = await InMemoryTransport.createConnectedPair()

        let client = Client(name: "TestClient", version: "1.0")
        let server = Server(
            name: "TestServer",
            version: "1.0",
            capabilities: .init()
        )

        let observer = CancellationObserver()

        // Start server
        try await server.start(transport: serverTransport)

        // Slow ping handler that records when it is cancelled
        await server.withMethodHandler(Ping.self) { _ in
            do {
                try await Task.sleep(for: .seconds(5))
            } catch {
                await observer.mark()
                throw error
            }
            return Empty()
        }

        // Connect client
        _ = try await client.connect(transport: clientTransport)
        try await Task.sleep(for: .milliseconds(50))

        // Send a ping request
        let pingRequest = Ping.request()
        let context = try await client.send(pingRequest)

        try await Task.sleep(for: .milliseconds(50))

        // Cancel the request
        try await client.cancelRequest(context.requestID, reason: "Test cancellation")

        try await Task.sleep(for: .milliseconds(50))

        // The server received the notification and cancelled the in-flight handler
        #expect(await observer.waitForCancellation())

        // The cancelled request never yields a result on the client
        await #expect(throws: CancellationError.self) {
            _ = try await context.value
        }

        await client.disconnect()
        await server.stop()
    }

    @Test("Client receives and processes CancelledNotification")
    func testClientReceivesCancellation() async throws {
        let (clientTransport, serverTransport) = await InMemoryTransport.createConnectedPair()

        let client = Client(name: "TestClient", version: "1.0")
        let server = Server(
            name: "TestServer",
            version: "1.0",
            capabilities: .init()
        )

        // Start server and connect client
        try await server.start(transport: serverTransport)

        // Register a slow ping handler (must be after start to override default)
        await server.withMethodHandler(Ping.self) { _ in
            try await Task.sleep(for: .seconds(5))
            return Empty()
        }
        _ = try await client.connect(transport: clientTransport)
        try await Task.sleep(for: .milliseconds(50))

        // Send a request using send
        let pingRequest = Ping.request()
        let context = try await client.send(pingRequest)

        // Server cancels the request while it's being awaited
        try await Task.sleep(for: .milliseconds(50))
        try await server.cancelRequest(pingRequest.id, reason: "Server cancelled")

        // Try to get result - should throw CancellationError
        await #expect(throws: CancellationError.self) {
            _ = try await context.value
        }

        await client.disconnect()
        await server.stop()
    }

    @Test("RequestContext structure")
    func testRequestContextStructure() async throws {
        let (clientTransport, serverTransport) = await InMemoryTransport.createConnectedPair()

        let client = Client(name: "TestClient", version: "1.0")
        let server = Server(
            name: "TestServer",
            version: "1.0",
            capabilities: .init()
        )

        // Start server and connect client
        try await server.start(transport: serverTransport)
        _ = try await client.connect(transport: clientTransport)
        try await Task.sleep(for: .milliseconds(50))

        // Create a request with send
        let pingRequest = Ping.request()
        let context: RequestContext<Ping.Result> = try await client.send(pingRequest)

        // Verify the context has the correct requestID
        #expect(context.requestID == pingRequest.id)

        // Await the result through the context
        let result = try await context.value
        #expect(result == Empty())

        await client.disconnect()
        await server.stop()
    }

    @Test("callTool with RequestContext overload")
    func testCallToolWithRequestContext() async throws {
        let (clientTransport, serverTransport) = await InMemoryTransport.createConnectedPair()

        let client = Client(name: "TestClient", version: "1.0")
        let server = Server(
            name: "TestServer",
            version: "1.0",
            capabilities: .init(tools: .init())
        )

        // Register a tool handler
        await server.withMethodHandler(ListTools.self) { _ in
            .init(tools: [Tool(name: "testTool", description: "A test tool", inputSchema: .object([:]))])
        }

        await server.withMethodHandler(CallTool.self) { params in
            return .init(content: [.text(text: "Result for \(params.name)", annotations: nil, _meta: nil)], isError: false)
        }

        // Start server and connect client
        try await server.start(transport: serverTransport)
        _ = try await client.connect(transport: clientTransport)
        try await Task.sleep(for: .milliseconds(50))

        // Use the callTool overload that returns RequestContext (non-async version)
        let context: RequestContext<CallTool.Result> = try await client.callTool(name: "testTool", arguments: ["test": "value"])

        // Verify we got a context
        #expect(context.requestID != ID(stringLiteral: ""))

        // Get the result
        let result = try await context.value
        #expect(result.content == [.text(text: "Result for testTool", annotations: nil, _meta: nil)])
        #expect(result.isError == false)

        await client.disconnect()
        await server.stop()
    }

    @Test("Cancel callTool using RequestContext overload")
    func testCancelCallToolWithRequestContext() async throws {
        let (clientTransport, serverTransport) = await InMemoryTransport.createConnectedPair()

        let client = Client(name: "TestClient", version: "1.0")
        let server = Server(
            name: "TestServer",
            version: "1.0",
            capabilities: .init(tools: .init())
        )

        // Register a tool handler that takes time
        await server.withMethodHandler(ListTools.self) { _ in
            .init(tools: [Tool(name: "slowTool", description: "A slow tool", inputSchema: .object([:]))])
        }

        let observer = CancellationObserver()
        await server.withMethodHandler(CallTool.self) { params in
            do {
                try await Task.sleep(for: .seconds(5))
            } catch {
                await observer.mark()
                throw error
            }
            return .init(content: [.text(text: "Should not reach here", annotations: nil, _meta: nil)], isError: false)
        }

        // Start server and connect client
        try await server.start(transport: serverTransport)
        _ = try await client.connect(transport: clientTransport)
        try await Task.sleep(for: .milliseconds(50))

        // Use the callTool overload that returns RequestContext (non-async version)
        let context: RequestContext<CallTool.Result> = try await client.callTool(name: "slowTool", arguments: [:])

        // Cancel after a short delay
        try await Task.sleep(for: .milliseconds(50))
        try await client.cancelRequest(context.requestID, reason: "Test timeout")

        // Try to get result - should throw CancellationError
        await #expect(throws: CancellationError.self) {
            _ = try await context.value
        }

        // The server-side tool handler observed the cancellation
        #expect(await observer.waitForCancellation())

        await client.disconnect()
        await server.stop()
    }

    @Test("CancelledNotification prevents response")
    func testCancellationPreventsResponse() async throws {
        let (clientTransport, serverTransport) = await InMemoryTransport.createConnectedPair()

        let client = Client(name: "TestClient", version: "1.0")
        let server = Server(
            name: "TestServer",
            version: "1.0",
            capabilities: .init()
        )

        // Start server and connect client
        try await server.start(transport: serverTransport)

        // Register a slow handler (must be after start to override default)
        let observer = CancellationObserver()
        await server.withMethodHandler(Ping.self) { _ in
            do {
                try await Task.sleep(for: .seconds(10))
            } catch {
                await observer.mark()
                throw error
            }
            return Empty()
        }
        _ = try await client.connect(transport: clientTransport)
        try await Task.sleep(for: .milliseconds(50))

        // Send a ping request
        let pingRequest = Ping.request()
        let context = try await client.send(pingRequest)

        // Cancel the request while it's being awaited
        try await Task.sleep(for: .milliseconds(50))
        try await client.cancelRequest(context.requestID, reason: "Test cancellation")

        // Try to get result - should throw CancellationError (proving no response was sent)
        await #expect(throws: CancellationError.self) {
            _ = try await context.value
        }

        // The handler was cancelled rather than completing, so no response was produced
        #expect(await observer.waitForCancellation())

        await client.disconnect()
        await server.stop()
    }
}
