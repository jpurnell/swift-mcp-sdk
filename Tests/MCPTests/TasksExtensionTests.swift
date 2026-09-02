import Foundation
import Testing

@testable import MCP

/// The `io.modelcontextprotocol/tasks` extension (SEP-2663).
///
/// MCP `2026-07-28` moved tasks out of the core protocol into an official extension. A task
/// carries work that outlives a single request: the server returns a `taskId`, the client polls
/// `tasks/get`, and mid-flight input is supplied through `tasks/update` rather than a
/// server-initiated request — which a stateless protocol has no channel for.
@Suite("Tasks Extension")
struct TasksExtensionTests {

    @Test("The extension identifier is the one capabilities negotiate on")
    func testExtensionIdentifier() {
        #expect(TasksExtension.identifier == "io.modelcontextprotocol/tasks")
    }

    @Test("The method names match the specification")
    func testMethodNames() {
        #expect(GetTask.name == "tasks/get")
        #expect(UpdateTask.name == "tasks/update")
        #expect(TasksExtension.statusNotification == "notifications/tasks")
    }

    @Test("Task statuses use the specification's wire values", arguments: [
        (TaskStatus.working, "working"),
        (TaskStatus.inputRequired, "input_required"),
        (TaskStatus.completed, "completed"),
        (TaskStatus.failed, "failed"),
        (TaskStatus.cancelled, "cancelled"),
    ])
    func testStatusWireValues(status: TaskStatus, wire: String) throws {
        #expect(status.rawValue == wire)
        let decoded = try JSONDecoder().decode(TaskStatus.self, from: Data("\"\(wire)\"".utf8))
        #expect(decoded == status)
    }

    /// `completed`, `failed` and `cancelled` are terminal: once reached the state does not
    /// change. A client that keeps polling a terminal task is wasting requests, so the type
    /// answers the question rather than leaving each caller to hardcode the set.
    @Test("Terminal statuses are identified as terminal")
    func testTerminalStatuses() {
        #expect(TaskStatus.completed.isTerminal)
        #expect(TaskStatus.failed.isTerminal)
        #expect(TaskStatus.cancelled.isTerminal)
        #expect(!TaskStatus.working.isTerminal)
        #expect(!TaskStatus.inputRequired.isTerminal)
    }

    @Test("A task round-trips through the wire format")
    func testTaskRoundTrip() throws {
        let task = MCPTask(
            taskId: "task-1",
            status: .working,
            statusMessage: "processing 3 of 10",
            createdAt: "2026-09-01T12:00:00Z",
            lastUpdatedAt: "2026-09-01T12:00:05Z",
            ttlMs: 600_000,
            pollIntervalMs: 2_000
        )

        let decoded = try JSONDecoder().decode(MCPTask.self, from: try JSONEncoder().encode(task))
        #expect(decoded.taskId == "task-1")
        #expect(decoded.status == .working)
        #expect(decoded.statusMessage == "processing 3 of 10")
        #expect(decoded.ttlMs == 600_000)
        #expect(decoded.pollIntervalMs == 2_000)
    }

    /// `ttlMs` is `number | null` in the specification, where null means unlimited — which is
    /// not the same as absent, and must survive a round trip as an explicit null.
    @Test("A null ttl means unlimited and is distinct from an absent one")
    func testNullTTLIsExplicit() throws {
        let unlimited = MCPTask(
            taskId: "t", status: .working,
            createdAt: "2026-09-01T12:00:00Z", lastUpdatedAt: "2026-09-01T12:00:00Z",
            ttlMs: nil)

        let data = try JSONEncoder().encode(unlimited)
        let asDictionary = try JSONDecoder().decode([String: Value].self, from: data)
        #expect(asDictionary["ttlMs"] == .null, "unlimited is an explicit null, not an omission")

        let decoded = try JSONDecoder().decode(MCPTask.self, from: data)
        #expect(decoded.ttlMs == nil)
    }

    /// A task awaiting input carries the same `InputRequests` shape MRTR uses, so a client that
    /// already fulfils MRTR needs no second mechanism.
    @Test("A task awaiting input carries MRTR input requests")
    func testInputRequiredCarriesRequests() throws {
        let result = GetTask.Result(
            task: MCPTask(
                taskId: "t", status: .inputRequired,
                createdAt: "2026-09-01T12:00:00Z", lastUpdatedAt: "2026-09-01T12:00:00Z",
                ttlMs: nil),
            inputRequests: ["needs-roots": .listRoots(Empty())])

        let decoded = try JSONDecoder().decode(
            GetTask.Result.self, from: try JSONEncoder().encode(result))

        #expect(decoded.task.status == .inputRequired)
        #expect(decoded.inputRequests?.count == 1)
    }

    @Test("An update carries responses keyed to the requests")
    func testUpdateCarriesResponses() throws {
        let params = UpdateTask.Parameters(
            taskId: "t",
            inputResponses: ["needs-roots": .listRoots(ListRoots.Result(roots: []))])

        let decoded = try JSONDecoder().decode(
            UpdateTask.Parameters.self, from: try JSONEncoder().encode(params))

        #expect(decoded.taskId == "t")
        #expect(decoded.inputResponses?.keys.contains("needs-roots") == true)
    }
}
