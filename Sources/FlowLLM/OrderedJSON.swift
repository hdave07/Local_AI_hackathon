import Foundation

/// A JSON value whose object keys serialize in the order given.
///
/// Why: Swift `Dictionary` iteration order is randomized per process, and LM Studio's
/// schema-constrained decoding emits properties in the schema's `properties` order.
/// With a dictionary-built schema, every launch asked Bonsai for a different field
/// order, which changed its answers at temperature 0 (T-002 evidence). Object key
/// order is therefore part of the model contract and must be fixed.
public indirect enum OrderedJSON: Sendable, Equatable {
    case string(String)
    case int(Int)
    case bool(Bool)
    case null
    case array([OrderedJSON])
    case object([(String, OrderedJSON)])

    public static func == (lhs: OrderedJSON, rhs: OrderedJSON) -> Bool {
        lhs.serialized() == rhs.serialized()
    }

    public func serialized() -> Data {
        var out = ""
        write(into: &out)
        return Data(out.utf8)
    }

    private func write(into out: inout String) {
        switch self {
        case .string(let s): out += Self.quote(s)
        case .int(let i): out += String(i)
        case .bool(let b): out += b ? "true" : "false"
        case .null: out += "null"
        case .array(let items):
            out += "["
            for (i, item) in items.enumerated() {
                if i > 0 { out += "," }
                item.write(into: &out)
            }
            out += "]"
        case .object(let members):
            out += "{"
            for (i, (key, value)) in members.enumerated() {
                if i > 0 { out += "," }
                out += Self.quote(key) + ":"
                value.write(into: &out)
            }
            out += "}"
        }
    }

    /// RFC 8259 string escaping.
    static func quote(_ s: String) -> String {
        var r = "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": r += "\\\""
            case "\\": r += "\\\\"
            case "\n": r += "\\n"
            case "\r": r += "\\r"
            case "\t": r += "\\t"
            case _ where scalar.value < 0x20: r += String(format: "\\u%04x", scalar.value)
            default: r.unicodeScalars.append(scalar)
            }
        }
        return r + "\""
    }
}
