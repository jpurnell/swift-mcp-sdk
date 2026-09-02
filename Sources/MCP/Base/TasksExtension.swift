import Foundation

/// The `io.modelcontextprotocol/tasks` extension (SEP-2663).
///
/// MCP `2026-07-28` moved tasks out of the core protocol into an official extension. A task
/// carries work that outlives a single request: the server returns a `taskId`, the client polls
/// ``GetTask``, and mid-flight input arrives through ``UpdateTask`` rather than a
/// server-initiated request — which a stateless protocol has no channel for.
///
/// Being an extension, it is negotiated rather than assumed: a client declares it in its
/// per-request capabilities and a server advertises it in `server/discover`. A server that does
/// not advertise it is fully conformant.
public enum TasksExtension {
    /// The identifier capabilities negotiate on.
    public static let identifier = "io.modelcontextprotocol/tasks"
    /// The notification a server sends with a task's full state, delivered on a
    /// `subscriptions/listen` stream so a client need not poll.
    public static let statusNotification = "notifications/tasks"
}

/// Where a task is in its lifecycle.
public enum TaskStatus: String, Hashable, Codable, Sendable {
    /// The operation is in progress.
    case working
    /// The server needs client input before continuing; see the outstanding input requests.
    case inputRequired = "input_required"
    /// The operation finished, and the result is available.
    ///
    /// This includes a tool call that returned `isError: true` — that is a result, not a
    /// protocol failure.
    case completed
    /// A JSON-RPC error occurred during execution. Not used for non-JSON-RPC errors.
    case failed
    /// The operation was cancelled before completion.
    case cancelled

    /// Whether this status is final.
    ///
    /// `completed`, `failed` and `cancelled` are terminal: once reached the state does not
    /// change. Exposed here so a polling client can stop rather than each caller hardcoding the
    /// set and one of them getting it wrong.
    public var isTerminal: Bool {
        switch self {
        case .completed, .failed, .cancelled: return true
        case .working, .inputRequired: return false
        }
    }
}

/// Work that outlives the request that created it.
///
/// Named `MCPTask` rather than `Task` to avoid colliding with Swift concurrency's `Task`, which
/// would otherwise need qualifying at every use site in a codebase full of them.
public struct MCPTask: Hashable, Codable, Sendable {
    /// Stable identifier for this task.
    public let taskId: String
    /// Current status.
    public var status: TaskStatus
    /// Optional message describing the current state, which may be shown to a user or model.
    public var statusMessage: String?
    /// ISO 8601 timestamp when the task was created.
    public let createdAt: String
    /// ISO 8601 timestamp when the task was last updated.
    public var lastUpdatedAt: String
    /// Time-to-live from creation in milliseconds; `nil` means unlimited.
    ///
    /// The specification types this as `number | null`, where null means unlimited. That is not
    /// the same as the field being absent, so it is always encoded — as an explicit null when
    /// unlimited. The value may change over a task's lifetime.
    public var ttlMs: Int?
    /// Suggested polling interval in milliseconds, which clients should honour.
    public var pollIntervalMs: Int?

    /// Creates a task.
    ///
    /// - Parameters:
    ///   - taskId: Stable identifier.
    ///   - status: Current status.
    ///   - statusMessage: Optional human-readable state description.
    ///   - createdAt: ISO 8601 creation timestamp.
    ///   - lastUpdatedAt: ISO 8601 last-update timestamp.
    ///   - ttlMs: Time-to-live in milliseconds, or `nil` for unlimited.
    ///   - pollIntervalMs: Suggested polling interval in milliseconds.
    public init(
        taskId: String,
        status: TaskStatus,
        statusMessage: String? = nil,
        createdAt: String,
        lastUpdatedAt: String,
        ttlMs: Int?,
        pollIntervalMs: Int? = nil
    ) {
        self.taskId = taskId
        self.status = status
        self.statusMessage = statusMessage
        self.createdAt = createdAt
        self.lastUpdatedAt = lastUpdatedAt
        self.ttlMs = ttlMs
        self.pollIntervalMs = pollIntervalMs
    }

    private enum CodingKeys: String, CodingKey {
        case taskId, status, statusMessage, createdAt, lastUpdatedAt, ttlMs, pollIntervalMs
    }

    /// Encodes the task, writing `ttlMs` as an explicit null when unlimited.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(taskId, forKey: .taskId)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(statusMessage, forKey: .statusMessage)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(lastUpdatedAt, forKey: .lastUpdatedAt)
        // Always encoded: null means unlimited, which absence would not convey.
        try container.encode(ttlMs, forKey: .ttlMs)
        try container.encodeIfPresent(pollIntervalMs, forKey: .pollIntervalMs)
    }
}

/// Polls a task's state.
public enum GetTask: Method {
    /// The JSON-RPC method name.
    public static let name: String = "tasks/get"

    /// What to poll.
    public struct Parameters: Hashable, Codable, Sendable {
        /// The task to poll.
        public var taskId: String

        /// Creates the parameters.
        public init(taskId: String) { self.taskId = taskId }
    }

    /// The task's state, and anything it is waiting for.
    public struct Result: Hashable, Codable, Sendable {
        /// The task.
        public var task: MCPTask
        /// Outstanding input the server needs, when the status is `input_required`.
        ///
        /// The same shape MRTR uses, so a client that already fulfils input requests needs no
        /// second mechanism for tasks.
        public var inputRequests: [String: InputRequest]?
        /// The final result, when the task has completed.
        public var result: Value?
        /// Tells the client how to parse this result.
        public var resultType: ResultType?
        /// Optional metadata about this result.
        public var _meta: Metadata?

        /// Creates the result.
        ///
        /// - Parameters:
        ///   - task: The task state.
        ///   - inputRequests: Outstanding input requests, if any.
        ///   - result: The final result, if the task completed.
        ///   - resultType: How to parse this result.
        ///   - _meta: Optional metadata.
        public init(
            task: MCPTask,
            inputRequests: [String: InputRequest]? = nil,
            result: Value? = nil,
            resultType: ResultType? = nil,
            _meta: Metadata? = nil
        ) {
            self.task = task
            self.inputRequests = inputRequests
            self.result = result
            self.resultType = resultType
            self._meta = _meta
        }
    }
}

/// Supplies input a task is waiting on.
public enum UpdateTask: Method {
    /// The JSON-RPC method name.
    public static let name: String = "tasks/update"

    /// The responses a client is supplying.
    public struct Parameters: Hashable, Codable, Sendable {
        /// The task being updated.
        public var taskId: String
        /// Answers keyed to match the task's outstanding input requests.
        public var inputResponses: [String: InputResponse]?
        /// Metadata for this request.
        public var _meta: Metadata?

        /// Creates the parameters.
        ///
        /// - Parameters:
        ///   - taskId: The task being updated.
        ///   - inputResponses: Answers keyed to the outstanding requests.
        ///   - _meta: Optional metadata.
        public init(
            taskId: String,
            inputResponses: [String: InputResponse]? = nil,
            _meta: Metadata? = nil
        ) {
            self.taskId = taskId
            self.inputResponses = inputResponses
            self._meta = _meta
        }
    }

    /// The task's state after the update.
    public struct Result: Hashable, Codable, Sendable {
        /// The task.
        public var task: MCPTask
        /// Tells the client how to parse this result.
        public var resultType: ResultType?

        /// Creates the result.
        ///
        /// - Parameters:
        ///   - task: The updated task state.
        ///   - resultType: How to parse this result.
        public init(task: MCPTask, resultType: ResultType? = nil) {
            self.task = task
            self.resultType = resultType
        }
    }
}
