import Foundation

/// A JSON value, for JSON-RPC messages whose params vary by method.
public enum JSONValue: Codable, Sendable, Hashable {
    case null, bool(Bool), number(Double), string(String), array([JSONValue]), object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case let .bool(b): try c.encode(b)
        case let .number(n): if n == n.rounded(), abs(n) < 1e15 { try c.encode(Int64(n)) } else { try c.encode(n) }
        case let .string(s): try c.encode(s)
        case let .array(a): try c.encode(a)
        case let .object(o): try c.encode(o)
        }
    }

    public subscript(key: String) -> JSONValue? { if case let .object(o) = self { o[key] } else { nil } }
    public var string: String? { if case let .string(s) = self { s } else { nil } }
    public var number: Double? { if case let .number(n) = self { n } else { nil } }
}

struct Request: Decodable {
    var id: JSONValue?
    var method: String
    var params: JSONValue?
}

func encodeLine(_ value: JSONValue) -> String {
    let e = JSONEncoder()
    e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return String(decoding: (try? e.encode(value)) ?? Data("{}".utf8), as: UTF8.self)
}

func response(id: JSONValue, result: JSONValue) -> String {
    encodeLine(.object(["jsonrpc": .string("2.0"), "id": id, "result": result]))
}

func errorResponse(id: JSONValue, code: Int, message: String) -> String {
    encodeLine(.object(["jsonrpc": .string("2.0"), "id": id,
                        "error": .object(["code": .number(Double(code)), "message": .string(message)])]))
}
