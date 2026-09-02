import Foundation
import Testing

@testable import MCP

/// The wire shapes SEP-2663 v2 defines for the tasks surface.
///
/// v1 wrapped a task in a `task` key. v2 flattens it: `CreateTaskResult` is a `Result & Task`
/// intersection, with `taskId` and `status` at the top level and no wrapper. The distinction is
/// load-bearing rather than cosmetic — `resultType` is what a client switches on to tell a task
/// response from a completed one (SEP-2322), and a nested envelope puts the discriminator and
/// the thing it discriminates at different depths.
@Suite("Task envelopes")
struct TaskEnvelopeTests {

    private func encoded<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private var task: MCPTask {
        MCPTask(
            taskId: "task-1", status: .working,
            createdAt: "2026-09-02T00:00:00Z", lastUpdatedAt: "2026-09-02T00:00:01Z",
            ttlMs: 60_000, pollIntervalMs: 500)
    }

    // MARK: - CreateTaskResult

    @Test("A created task is flat, with no nested wrapper")
    func testCreateTaskResultIsFlat() throws {
        let json = try encoded(CreateTaskResult(task: task))

        #expect(json["task"] == nil, "there must be no nested task wrapper key")
        #expect(json["taskId"] as? String == "task-1")
        #expect(json["status"] as? String == "working")
        #expect(json["createdAt"] as? String == "2026-09-02T00:00:00Z")
        #expect(json["lastUpdatedAt"] as? String == "2026-09-02T00:00:01Z")
        #expect(json["ttlMs"] as? Int == 60_000)
    }

    /// `resultType` is the discriminator: a client reads it to know whether it received work in
    /// progress or an answer.
    @Test("A created task tags itself as a task")
    func testCreateTaskResultTag() throws {
        let json = try encoded(CreateTaskResult(task: task))
        #expect(json["resultType"] as? String == "task")
    }

    /// Creation says a task exists. What it produced belongs to `tasks/get`, and carrying it
    /// here would let a client read a result that is not final.
    @Test("A created task carries neither result, error nor inputRequests")
    func testCreateTaskResultCarriesNothingElse() throws {
        let json = try encoded(CreateTaskResult(task: task))
        #expect(json["result"] == nil)
        #expect(json["error"] == nil)
        #expect(json["inputRequests"] == nil)
    }

    /// `null` means unlimited, which is a different statement from the field being absent.
    @Test("An unlimited lifetime is an explicit null")
    func testUnlimitedTTLIsExplicitNull() throws {
        var unlimited = task
        unlimited.ttlMs = nil
        let data = try JSONEncoder().encode(CreateTaskResult(task: unlimited))
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(text.contains("\"ttlMs\":null"), "absent and unlimited are not the same claim")
    }

    // MARK: - tasks/get

    @Test("A polled task is flat too")
    func testGetTaskResultIsFlat() throws {
        let json = try encoded(GetTask.Result(task: task))

        #expect(json["task"] == nil)
        #expect(json["taskId"] as? String == "task-1")
        #expect(json["status"] as? String == "working")
    }

    /// A working task has produced nothing yet, and saying so by omission is what lets a client
    /// poll without special-casing.
    @Test("A working task inlines neither result nor error")
    func testWorkingTaskHasNoResult() throws {
        let json = try encoded(GetTask.Result(task: task))
        #expect(json["result"] == nil)
        #expect(json["error"] == nil)
    }

    /// There is no `tasks/result` method in v2: the result is inlined here or nowhere.
    @Test("A completed task inlines its result")
    func testCompletedTaskInlinesResult() throws {
        var completed = task
        completed.status = .completed
        let result = GetTask.Result(
            task: completed,
            result: .object(["content": .array([.object(["type": .string("text")])])]))

        let json = try encoded(result)
        #expect(json["status"] as? String == "completed")
        let inlined = try #require(json["result"] as? [String: Any])
        #expect(inlined["content"] as? [[String: Any]] != nil)
    }

    /// A tool that ran and reported failure is `completed` with `isError`; `failed` is reserved
    /// for a protocol error, which inlines an `error` object and no result. Conflating them
    /// tells a client the call never happened when in fact it ran and said no.
    @Test("A failed task inlines an error and no result")
    func testFailedTaskInlinesError() throws {
        var failed = task
        failed.status = .failed
        let result = GetTask.Result(
            task: failed,
            error: .init(code: -32603, message: "Internal error"))

        let json = try encoded(result)
        #expect(json["result"] == nil, "a protocol failure produced no result")
        let error = try #require(json["error"] as? [String: Any])
        #expect(error["code"] as? Int == -32603)
        #expect(error["message"] as? String == "Internal error")
    }

    // MARK: - tasks/cancel

    /// The ack is empty by design (SEP-2322's discriminator): cancellation is observed through
    /// the next `tasks/get`, not through what the cancel returns.
    @Test("Cancelling acknowledges with a complete result and no envelope")
    func testCancelAckIsEmpty() throws {
        let json = try encoded(CancelTask.Result())

        #expect(json["resultType"] as? String == "complete")
        #expect(json["taskId"] == nil, "the ack carries no task envelope")
        #expect(json["status"] == nil)
    }

    @Test("Cancelling names the method the specification gives it")
    func testCancelMethodName() {
        #expect(CancelTask.name == "tasks/cancel")
    }

    // MARK: - Round trips

    @Test("A created task decodes back to the same task")
    func testCreateTaskResultRoundTrips() throws {
        let data = try JSONEncoder().encode(CreateTaskResult(task: task))
        let decoded = try JSONDecoder().decode(CreateTaskResult.self, from: data)

        #expect(decoded.taskId == "task-1")
        #expect(decoded.status == .working)
        #expect(decoded.ttlMs == 60_000)
        #expect(decoded.resultType == .task)
    }

    @Test("A polled task decodes back with its inlined result")
    func testGetTaskResultRoundTrips() throws {
        var completed = task
        completed.status = .completed
        let original = GetTask.Result(task: completed, result: .object(["ok": .bool(true)]))

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(GetTask.Result.self, from: data)

        #expect(decoded.taskId == "task-1")
        #expect(decoded.status == .completed)
        #expect(decoded.result?.objectValue?["ok"]?.boolValue == true)
    }
}
