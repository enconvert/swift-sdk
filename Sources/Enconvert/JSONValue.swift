/** Enconvert — arbitrary JSON passthrough value. */

import Foundation

/// A JSON value used for caller-defined payloads that must round-trip
/// through the API untouched: extraction `schema`, distill `data`, watcher
/// `trackFields` / diff `changes`, lookup `extra` / `answerBox` /
/// `knowledgeGraph`, perceive `geolocation` / `actionChain`, and similar
/// free-form fields.
public enum JSONValue: Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])
}

extension JSONValue: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
    }
}

extension JSONValue {
    /// Builds a `JSONValue` from a `JSONSerialization`-produced object graph
    /// (`NSNull`, booleans, numbers, `String`, `[Any]`, `[String: Any]`).
    /// Order matters: `Bool` is checked before numeric types because
    /// `NSNumber`-boxed booleans also bridge to numeric `as?` casts.
    public static func from(_ any: Any) -> JSONValue {
        if any is NSNull { return .null }
        if let value = any as? Bool { return .bool(value) }
        if let value = any as? Int { return .number(Double(value)) }
        if let value = any as? Double { return .number(value) }
        if let value = any as? NSNumber { return .number(value.doubleValue) }
        if let value = any as? String { return .string(value) }
        if let value = any as? [Any] { return .array(value.map(JSONValue.from)) }
        if let value = any as? [String: Any] { return .object(value.mapValues(JSONValue.from)) }
        return .null
    }

    /// Converts back to a `JSONSerialization`-compatible object graph for
    /// embedding inside a request body dictionary.
    public var jsonSerializable: Any {
        switch self {
        case .null:
            return NSNull()
        case .bool(let value):
            return value
        case .number(let value):
            return value
        case .string(let value):
            return value
        case .array(let value):
            return value.map { $0.jsonSerializable }
        case .object(let value):
            return value.mapValues { $0.jsonSerializable }
        }
    }

    /// Convenience accessor when the value is expected to be a JSON object.
    public var objectValue: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }
}

/// A JSON object payload (`Record<string, unknown>` in the Node SDK).
public typealias JSONObject = [String: JSONValue]

extension JSONObject {
    /// Converts to a `JSONSerialization`-compatible `[String: Any]`.
    public var jsonSerializable: [String: Any] {
        mapValues { $0.jsonSerializable }
    }

    /// Builds a `JSONObject` from a `[String: Any]` (e.g. a parsed API response).
    public static func from(_ dict: [String: Any]) -> JSONObject {
        dict.mapValues { JSONValue.from($0) }
    }
}
