import Foundation

/// A small, Sendable JSON tree used to build analyzer request bodies and to read provider responses without
/// committing to rigid `Codable` structs (provider responses carry many optional, loosely typed members).
public enum AnalysisJSON: Sendable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([AnalysisJSON])
    case object([String: AnalysisJSON])

    // MARK: Accessors

    public subscript(key: String) -> AnalysisJSON? {
        if case .object(let o) = self { return o[key] }
        return nil
    }

    public subscript(index: Int) -> AnalysisJSON? {
        if case .array(let a) = self, a.indices.contains(index) { return a[index] }
        return nil
    }

    public var stringValue: String? { if case .string(let s) = self { return s }; return nil }
    public var doubleValue: Double? { if case .number(let n) = self { return n }; return nil }
    public var intValue: Int? {
        guard case .number(let n) = self, n.isFinite, n == n.rounded(), abs(n) < 9.0e15 else { return nil }
        return Int(n)
    }
    public var boolValue: Bool? { if case .bool(let b) = self { return b }; return nil }
    public var arrayValue: [AnalysisJSON]? { if case .array(let a) = self { return a }; return nil }
    public var objectValue: [String: AnalysisJSON]? { if case .object(let o) = self { return o }; return nil }
    public var isNull: Bool { self == .null }

    // MARK: Serialization

    /// Parses UTF-8 JSON. Throws on malformed input. Accepts top-level scalars.
    public static func parse(_ data: Data) throws -> AnalysisJSON {
        try JSONDecoder().decode(AnalysisJSON.self, from: data)
    }

    public static func parse(_ text: String) throws -> AnalysisJSON {
        try parse(Data(text.utf8))
    }

    /// Compact JSON with sorted keys (deterministic, so tests can compare bodies byte for byte).
    public func encoded(pretty: Bool = false) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
                                          : [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}

extension AnalysisJSON: Codable {
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let n = try? c.decode(Double.self) { self = .number(n); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let a = try? c.decode([AnalysisJSON].self) { self = .array(a); return }
        if let o = try? c.decode([String: AnalysisJSON].self) { self = .object(o); return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unsupported JSON value")
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let n):
            // Integral values encode without a fractional part ("60", not "60.0").
            if n.isFinite, n == n.rounded(), abs(n) < 9.0e15 { try c.encode(Int64(n)) } else { try c.encode(n) }
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }
}

extension AnalysisJSON: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral,
    ExpressibleByBooleanLiteral, ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral, ExpressibleByNilLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
    public init(integerLiteral value: Int) { self = .number(Double(value)) }
    public init(floatLiteral value: Double) { self = .number(value) }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(arrayLiteral elements: AnalysisJSON...) { self = .array(elements) }
    public init(dictionaryLiteral elements: (String, AnalysisJSON)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { _, last in last }))
    }
    public init(nilLiteral: ()) { self = .null }
}
