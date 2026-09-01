import Foundation

/// A request the server needs the client to fulfil before it can finish the original call.
///
/// Part of Multi Round-Trip Requests (MRTR), introduced by MCP `2026-07-28` (SEP-2322). Earlier
/// revisions let a server initiate `roots/list`, `sampling/createMessage` or
/// `elicitation/create` on its own; a stateless protocol has no open channel to push those
/// down, so the server names what it needs and the client answers on a retry.
public enum InputRequest: Hashable, Sendable {
    /// The server needs the client to sample from a model.
    case createMessage(CreateSamplingMessage.Parameters)
    /// The server needs the client's roots.
    case listRoots(Empty)
    /// The server needs the client to ask the user something.
    case elicit(CreateElicitation.Parameters)
}

/// A client's answer to one ``InputRequest``.
public enum InputResponse: Hashable, Sendable {
    /// The sampled message.
    case createMessage(CreateSamplingMessage.Result)
    /// The client's roots.
    case listRoots(ListRoots.Result)
    /// The user's answer.
    case elicit(CreateElicitation.Result)
}

/// An interim result: the server cannot finish yet and is naming what it needs.
///
/// The client fulfils each entry in ``inputRequests`` and **retries the original request**,
/// attaching the answers and echoing ``requestState`` back. There is no separate "continue"
/// method — the retry *is* the continuation, which is what keeps the exchange stateless.
public struct InputRequiredResult: Hashable, Codable, Sendable {
    /// Always ``ResultType/inputRequired``. This tag is what tells a client to retry rather
    /// than treat the payload as final content.
    public let resultType: ResultType
    /// What the server needs, keyed by server-assigned identifiers.
    ///
    /// The client answers under the same keys; that correspondence is the only thing tying an
    /// answer to the question it answers.
    public var inputRequests: [String: InputRequest]?
    /// Opaque server state to echo back on the retry.
    ///
    /// The client must not interpret or modify it. It is how the server correlates a retry
    /// with work it has already done, which is what saves it from redoing that work.
    public var requestState: String?
    /// Optional metadata about this result.
    public var _meta: Metadata?

    public init(
        inputRequests: [String: InputRequest]? = nil,
        requestState: String? = nil,
        _meta: Metadata? = nil
    ) {
        self.resultType = .inputRequired
        self.inputRequests = inputRequests
        self.requestState = requestState
        self._meta = _meta
    }

    private enum CodingKeys: String, CodingKey {
        case resultType, inputRequests, requestState, _meta
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        resultType =
            try container.decodeIfPresent(ResultType.self, forKey: .resultType) ?? .inputRequired
        inputRequests = try container.decodeIfPresent(
            [String: InputRequest].self, forKey: .inputRequests)
        requestState = try container.decodeIfPresent(String.self, forKey: .requestState)
        _meta = try container.decodeIfPresent(Metadata.self, forKey: ._meta)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(resultType, forKey: .resultType)
        try container.encodeIfPresent(inputRequests, forKey: .inputRequests)
        try container.encodeIfPresent(requestState, forKey: .requestState)
        try container.encodeIfPresent(_meta, forKey: ._meta)
    }
}

/// The parameters a client attaches when retrying a request that returned
/// ``InputRequiredResult``.
public struct InputResponseRequestParams: Hashable, Codable, Sendable {
    /// The client's answers, keyed to match the server's ``InputRequiredResult/inputRequests``.
    public var inputResponses: [String: InputResponse]?
    /// The opaque state the server sent, echoed back unmodified.
    public var requestState: String?
    /// Metadata for the retried request.
    ///
    /// Required by the specification on this params object, because the retry is an ordinary
    /// request and so still carries its own protocol version and client capabilities.
    public var _meta: Metadata?

    public init(
        inputResponses: [String: InputResponse]? = nil,
        requestState: String? = nil,
        _meta: Metadata? = nil
    ) {
        self.inputResponses = inputResponses
        self.requestState = requestState
        self._meta = _meta
    }
}

// MARK: - Coding

// `InputRequest` and `InputResponse` are `anyOf` unions in the schema with no discriminator
// field, so decoding tries each case in turn. Order matters: the most constrained shape is
// tried first, because `Empty` accepts any object and would otherwise swallow the others.

extension InputRequest: Codable {
    public init(from decoder: Decoder) throws {
        if let value = try? CreateSamplingMessage.Parameters(from: decoder) {
            self = .createMessage(value)
            return
        }
        if let value = try? CreateElicitation.Parameters(from: decoder) {
            self = .elicit(value)
            return
        }
        self = .listRoots(try Empty(from: decoder))
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .createMessage(let value): try value.encode(to: encoder)
        case .elicit(let value): try value.encode(to: encoder)
        case .listRoots(let value): try value.encode(to: encoder)
        }
    }
}

extension InputResponse: Codable {
    public init(from decoder: Decoder) throws {
        if let value = try? CreateSamplingMessage.Result(from: decoder) {
            self = .createMessage(value)
            return
        }
        if let value = try? CreateElicitation.Result(from: decoder) {
            self = .elicit(value)
            return
        }
        self = .listRoots(try ListRoots.Result(from: decoder))
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .createMessage(let value): try value.encode(to: encoder)
        case .elicit(let value): try value.encode(to: encoder)
        case .listRoots(let value): try value.encode(to: encoder)
        }
    }
}
