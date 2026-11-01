internal import AemiJSON

/// A JSON Schema value a tool's input takes, typed so a definition is right by construction: written through the stream writer, never
/// parsed from text (ADR-0141). Only what tools need: limits that a model reading the schema can respect, and objects that refuse fields
/// they do not name.
public indirect enum ToolSchema: Sendable, Equatable {
    case string(maxLength: Int? = nil, pattern: String? = nil)
    case integer(minimum: Int? = nil, maximum: Int? = nil)
    case boolean
    /// One of these strings.
    case choice([String])
    case array(ToolSchema, minItems: Int? = nil, maxItems: Int? = nil)
    /// An object with these fields, `required` among them; `closed` refuses any other (`additionalProperties: false`).
    case object([Field], required: [String] = [], closed: Bool = false)

    /// A named field of an object.
    public struct Field: Sendable, Equatable {
        public let name: String
        public let schema: ToolSchema

        public init(_ name: String, _ schema: ToolSchema) {
            self.name = name
            self.schema = schema
        }
    }

    func write(into writer: inout JSONStreamWriter) {
        writer.object { writer in
            switch self {
                case .string(let maxLength, let pattern):
                    writer.field("type", "string")
                    if let maxLength { writer.field("maxLength", maxLength) }
                    if let pattern { writer.field("pattern", pattern) }
                case .integer(let minimum, let maximum):
                    writer.field("type", "integer")
                    if let minimum { writer.field("minimum", minimum) }
                    if let maximum { writer.field("maximum", maximum) }
                case .boolean: writer.field("type", "boolean")
                case .choice(let values):
                    writer.key("enum")
                    writer.array { writer in for value in values { writer.string(value) } }
                case .array(let items, let minItems, let maxItems):
                    writer.field("type", "array")
                    if let minItems { writer.field("minItems", minItems) }
                    if let maxItems { writer.field("maxItems", maxItems) }
                    writer.key("items")
                    items.write(into: &writer)
                case .object(let fields, let required, let closed):
                    Self.writeObject(fields, required, closed, into: &writer)
            }
        }
    }

    /// The body of an object schema, without its braces: also what a tool's whole input writes.
    static func writeObject(
        _ fields: [Field],
        _ required: [String],
        _ closed: Bool,
        into writer: inout JSONStreamWriter
    ) {
        writer.field("type", "object")
        if closed { writer.field("additionalProperties", false) }
        writer.key("properties")
        writer.object { writer in
            for field in fields {
                writer.key(field.name)
                field.schema.write(into: &writer)
            }
        }
        if !required.isEmpty {
            writer.key("required")
            writer.array { writer in for name in required { writer.string(name) } }
        }
    }
}
