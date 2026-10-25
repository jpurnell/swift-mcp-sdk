import struct Foundation.UUID

/// The JSON-RPC `id` that correlates a request with its response: either a string or an integer.
public enum ID: Hashable, Sendable {
    /// A string ID.
    case string(String)

    /// A number ID.
    case number(Int)

    /// A fresh string ID built from a random UUID, suitable for correlating a new request.
    public static var random: ID {
        return .string(UUID().uuidString)
    }
}

// MARK: - ExpressibleByStringLiteral

extension ID: ExpressibleByStringLiteral {
    /// Creates a string ID from a string literal, so `let id: ID = "abc"` yields `.string("abc")`.
    ///
    /// - Parameter value: The literal text, used verbatim as the ID.
    public init(stringLiteral value: String) {
        self = .string(value)
    }
}

// MARK: - ExpressibleByIntegerLiteral

extension ID: ExpressibleByIntegerLiteral {
    /// Creates a numeric ID from an integer literal, so `let id: ID = 7` yields `.number(7)`.
    ///
    /// - Parameter value: The literal integer, used verbatim as the ID.
    public init(integerLiteral value: Int) {
        self = .number(value)
    }
}

// MARK: - CustomStringConvertible

extension ID: CustomStringConvertible {
    /// The ID rendered as text: the string itself, or the decimal form of the number.
    public var description: String {
        switch self {
        case .string(let str): return str
        case .number(let num): return String(num)
        }
    }
}

// MARK: - Codable

extension ID: Codable {
    /// Decodes an ID from a JSON string or number. A `null` ID reads as the empty string.
    ///
    /// - Parameter decoder: The decoder to read from.
    /// - Throws: `DecodingError` if the value is neither a string, a number nor `null`.
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let number = try? container.decode(Int.self) {
            self = .number(number)
        } else if container.decodeNil() {
            // Handle unspecified/null IDs as empty string
            self = .string("")
        } else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "ID must be string or number")
        }
    }

    /// Encodes the ID as a bare JSON string or number.
    ///
    /// - Parameter encoder: The encoder to write to.
    /// - Throws: Any error raised while encoding.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let str): try container.encode(str)
        case .number(let num): try container.encode(num)
        }
    }
}
