import Foundation

/// The wire shapes SEP-2663 v2 gives the tasks surface.
///
/// v1 wrapped a task inside a `task` key. v2 flattens it: a task response is a `Result & Task`
/// intersection, with `taskId` and `status` at the top level. The difference is load-bearing
/// rather than cosmetic — ``ResultType`` is the discriminator a client switches on to tell a
/// task response from a finished one, and a nested envelope puts the discriminator and the
/// thing it discriminates at different depths.
///
/// The task's own fields are modelled once, by ``MCPTask``; these types spread it across the
/// wire rather than restating it, so a field added there cannot go missing here.

// MARK: - Coding

/// The keys a flat task envelope writes, shared by every shape below so they cannot drift.
private enum TaskEnvelopeKeys: String, CodingKey {
    case taskId, status, statusMessage, createdAt, lastUpdatedAt, ttlMs, pollIntervalMs
    case resultType, result, error, inputRequests, _meta
}

extension MCPTask {
    /// Writes the task's own fields into a container that also holds result fields.
    fileprivate func encodeFlat(into container: inout KeyedEncodingContainer<TaskEnvelopeKeys>)
        throws
    {
        try container.encode(taskId, forKey: .taskId)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(statusMessage, forKey: .statusMessage)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(lastUpdatedAt, forKey: .lastUpdatedAt)
        // Always written: `null` means unlimited, which absence would not convey.
        try container.encode(ttlMs, forKey: .ttlMs)
        try container.encodeIfPresent(pollIntervalMs, forKey: .pollIntervalMs)
    }

    /// Reads a task back out of a flat envelope.
    fileprivate init(flat container: KeyedDecodingContainer<TaskEnvelopeKeys>) throws {
        self.init(
            taskId: try container.decode(String.self, forKey: .taskId),
            status: try container.decode(TaskStatus.self, forKey: .status),
            statusMessage: try container.decodeIfPresent(String.self, forKey: .statusMessage),
            createdAt: try container.decode(String.self, forKey: .createdAt),
            lastUpdatedAt: try container.decode(String.self, forKey: .lastUpdatedAt),
            ttlMs: try container.decodeIfPresent(Int.self, forKey: .ttlMs),
            pollIntervalMs: try container.decodeIfPresent(Int.self, forKey: .pollIntervalMs)
        )
    }
}

/// A JSON-RPC error inlined into a failed task.
///
/// `MCPError` is an enum over the codes this SDK knows; a task's inlined error is whatever the
/// failing operation reported, including codes from elsewhere, so it is carried structurally.
public struct TaskError: Hashable, Codable, Sendable {
    /// The JSON-RPC error code.
    public var code: Int
    /// A short description of what went wrong.
    public var message: String
    /// Anything the error carries beyond its message.
    public var data: Value?

    /// Creates an inlined error.
    ///
    /// - Parameters:
    ///   - code: The JSON-RPC error code.
    ///   - message: A short description.
    ///   - data: Structured detail, if the error defines any.
    public init(code: Int, message: String, data: Value? = nil) {
        self.code = code
        self.message = message
        self.data = data
    }
}

// MARK: - Creation

/// The response to a request the server chose to run as a task.
///
/// Flat by specification: `taskId` and `status` sit alongside `resultType`, with no wrapper. It
/// says a task exists and nothing about what it produced — the outcome belongs to ``GetTask``,
/// and carrying it here would let a client read a result that is not final.
public struct CreateTaskResult: Hashable, Codable, Sendable {
    /// The task that was created.
    public var task: MCPTask
    /// Always ``ResultType/task``, which is how a client tells this from a finished result.
    public var resultType: ResultType

    /// The task's identifier.
    public var taskId: String { task.taskId }
    /// Where the task is in its lifecycle.
    public var status: TaskStatus { task.status }
    /// How long the task remains readable, or `nil` for unlimited.
    public var ttlMs: Int? { task.ttlMs }

    /// Announces a newly created task.
    ///
    /// - Parameter task: The task the server created.
    public init(task: MCPTask) {
        self.task = task
        self.resultType = .task
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: TaskEnvelopeKeys.self)
        try task.encodeFlat(into: &container)
        try container.encode(resultType, forKey: .resultType)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: TaskEnvelopeKeys.self)
        self.task = try MCPTask(flat: container)
        self.resultType = try container.decodeIfPresent(ResultType.self, forKey: .resultType)
            ?? .task
    }
}

// MARK: - Cancellation

/// Asks the server to stop a task.
///
/// The acknowledgement is deliberately empty: cancellation is *requested* here and *observed*
/// through the next ``GetTask``, because a server that has already finished the work cannot
/// honestly report `cancelled` in the same breath as being asked to.
public enum CancelTask: Method {
    /// The JSON-RPC method name.
    public static let name: String = "tasks/cancel"

    /// Which task to stop.
    public struct Parameters: Hashable, Codable, Sendable {
        /// The task to cancel.
        public var taskId: String
        /// Metadata for this request. See ``GetTask/Parameters/_meta``.
        public var _meta: Metadata?

        /// Creates the parameters.
        ///
        /// - Parameters:
        ///   - taskId: The task to cancel.
        ///   - _meta: Optional request metadata.
        public init(taskId: String, _meta: Metadata? = nil) {
            self.taskId = taskId
            self._meta = _meta
        }
    }

    /// An empty acknowledgement.
    ///
    /// Carries no task envelope — SEP-2322's discriminator distinguishes this from a task
    /// response — and is the same answer for a task that has already reached a terminal state,
    /// which makes cancelling idempotent. `-32602` is reserved for a `taskId` the server does
    /// not recognise.
    public struct Result: Hashable, Codable, Sendable {
        /// Always ``ResultType/complete``: the acknowledgement itself is finished.
        public var resultType: ResultType

        /// Acknowledges a cancellation request.
        public init() { self.resultType = .complete }

        private enum CodingKeys: String, CodingKey { case resultType }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.resultType = try container.decodeIfPresent(ResultType.self, forKey: .resultType)
                ?? .complete
        }
    }
}

// MARK: - Polling

/// A task's full state, flat, with whatever it has produced inlined.
///
/// Replaces the v1 shape that nested the task under a `task` key. There is no
/// `tasks/result` method in v2: a completed task's result is inlined here or it is nowhere.
public struct DetailedTask: Hashable, Codable, Sendable {
    /// The task.
    public var task: MCPTask
    /// The result of the work, once the task has completed.
    ///
    /// A tool that ran and reported failure is `completed` with `isError` set inside this
    /// result. `failed` is reserved for a protocol error, which inlines ``error`` instead —
    /// conflating them tells a client the call never happened when in fact it ran and said
    /// no.
    public var result: Value?
    /// The protocol error that ended the task, when the status is `failed`.
    public var error: TaskError?
    /// What the server is waiting for, when the status is `input_required`.
    ///
    /// The same shape MRTR uses, so a client that already fulfils input requests needs no
    /// second mechanism for tasks.
    public var inputRequests: [String: InputRequest]?
    /// How to read this result.
    public var resultType: ResultType?
    /// Optional metadata about this result.
    public var _meta: Metadata?

    /// The task's identifier.
    public var taskId: String { task.taskId }
    /// Where the task is in its lifecycle.
    public var status: TaskStatus { task.status }

    /// Reports a task's state.
    ///
    /// - Parameters:
    ///   - task: The task.
    ///   - result: The completed result, if it has one.
    ///   - error: The protocol error that ended it, if it failed.
    ///   - inputRequests: What it is waiting for, if anything.
    ///   - resultType: How to read this result.
    ///   - _meta: Optional metadata.
    public init(
        task: MCPTask,
        result: Value? = nil,
        error: TaskError? = nil,
        inputRequests: [String: InputRequest]? = nil,
        resultType: ResultType? = .complete,
        _meta: Metadata? = nil
    ) {
        self.task = task
        self.result = result
        self.error = error
        self.inputRequests = inputRequests
        self.resultType = resultType
        self._meta = _meta
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: TaskEnvelopeKeys.self)
        try task.encodeFlat(into: &container)
        try container.encodeIfPresent(resultType, forKey: .resultType)
        try container.encodeIfPresent(result, forKey: .result)
        try container.encodeIfPresent(error, forKey: .error)
        try container.encodeIfPresent(inputRequests, forKey: .inputRequests)
        try container.encodeIfPresent(_meta, forKey: ._meta)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: TaskEnvelopeKeys.self)
        self.task = try MCPTask(flat: container)
        self.resultType = try container.decodeIfPresent(ResultType.self, forKey: .resultType)
        self.result = try container.decodeIfPresent(Value.self, forKey: .result)
        self.error = try container.decodeIfPresent(TaskError.self, forKey: .error)
        self.inputRequests = try container.decodeIfPresent(
            [String: InputRequest].self, forKey: .inputRequests)
        self._meta = try container.decodeIfPresent(Metadata.self, forKey: ._meta)
    }
}
