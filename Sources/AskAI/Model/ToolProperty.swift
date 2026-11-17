internal import AemiJSON

/// One property of a tool's input, as the model is told about it.
///
/// Built with ``string(_:minLength:)``, ``integer(_:minimum:maximum:)`` and ``boolean(_:)``, required unless
/// marked ``optional``, and saying what it is with ``described(_:)``. Declared inside ``ToolDefinition/init(name:description:properties:)``, so a tool states
/// its input once, in a form the compiler checks, instead of as a JSON string beside the struct that decodes it.
public struct ToolProperty: Sendable {
    let name: String
    let isRequired: Bool
    private let constraints: [Constraint]
    private let type: String
    /// A whole schema, written as given, for a property the simple constructors cannot describe.
    private let schema: [UInt8]?
    /// What the model is told this property is, beside its name and type.
    private let description: String?

    private enum Constraint: Sendable {
        case minLength(Int)
        case minimum(Int)
        case maximum(Int)
    }

    private init(
        _ name: String,
        type: String,
        isRequired: Bool = true,
        constraints: [Constraint] = [],
        schema: [UInt8]? = nil,
        description: String? = nil
    ) {
        self.name = name
        self.type = type
        self.isRequired = isRequired
        self.constraints = constraints
        self.schema = schema
        self.description = description
    }

    /// A property whose schema is `json`, compact JSON written verbatim: an object with its own properties.
    /// - Precondition: `json` is valid, compact JSON; it is spliced into the tool's schema unchanged.
    public static func schema(_ name: String, _ json: String) -> ToolProperty {
        ToolProperty(name, type: "object", schema: Array(json.utf8))
    }

    /// A string, optionally with a minimum length.
    public static func string(_ name: String, minLength: Int? = nil) -> ToolProperty {
        ToolProperty(name, type: "string", constraints: minLength.map { [.minLength($0)] } ?? [])
    }

    /// An integer, optionally bounded on either side.
    public static func integer(_ name: String, minimum: Int? = nil, maximum: Int? = nil) -> ToolProperty {
        ToolProperty(
            name,
            type: "integer",
            constraints: (minimum.map { [.minimum($0)] } ?? []) + (maximum.map { [.maximum($0)] } ?? [])
        )
    }

    /// A boolean.
    public static func boolean(_ name: String) -> ToolProperty { ToolProperty(name, type: "boolean") }

    /// This property, which the model may leave out.
    public var optional: ToolProperty {
        ToolProperty(
            name,
            type: type,
            isRequired: false,
            constraints: constraints,
            schema: schema,
            description: description
        )
    }

    /// This property, saying what it is: one phrase a model reads where it writes the value, so a tool's own description is left
    /// to say what the tool is for (ADR-0157).
    public func described(_ text: String) -> ToolProperty {
        ToolProperty(
            name,
            type: type,
            isRequired: isRequired,
            constraints: constraints,
            schema: schema,
            description: text
        )
    }

    /// Writes this property's schema: its type, then its constraints in the order given, then what it is.
    func writeSchema(into writer: inout JSONStreamWriter) {
        if let schema {
            guard let description, schema.last == UInt8(ascii: "}"), schema.count > 2 else {
                writer.raw(schema)
                return
            }
            // A schema written as given says what it is last, as the others do: spliced in before its closing brace.
            var quoted = JSONStreamWriter(capacity: description.utf8.count + 2)
            quoted.string(description)
            writer.raw(schema.dropLast() + Array(#","description":"#.utf8) + quoted.finish() + [UInt8(ascii: "}")])
            return
        }
        writer.object { writer in
            writer.field("type", type)
            for constraint in constraints {
                switch constraint {
                    case .minLength(let value): writer.field("minLength", value)
                    case .minimum(let value): writer.field("minimum", value)
                    case .maximum(let value): writer.field("maximum", value)
                }
            }
            if let description { writer.field("description", description) }
        }
    }
}
