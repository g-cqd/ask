internal import AemiJSON
internal import AskAI
internal import FoundationModels

/// A tool's JSON Schema as the framework's own generation schema, so the model's arguments are produced under constraint, as typed
/// values, and never as text that has to be repaired afterwards.
///
/// Only what a call's arguments need is carried: objects, arrays, strings, numbers, integers, booleans and string enums. Anything
/// else becomes a string. Properties that spend the small window on nothing a three-billion-parameter model could use (the
/// `sandbox` argument every tool takes) are left out.
enum AppleToolSchema {
    /// How much of a description the model reads: all of it (up to a generous cut), or its first sentence when the window is short.
    enum Detail {
        case full, brief

        var limit: Int { self == .full ? 600 : 120 }
    }

    /// The generation schema for `inputSchema`, a JSON Schema object's bytes; nil when it is not an object schema this can express.
    static func schema(
        named name: String, description: String, inputSchema: [UInt8], detail: Detail = .full
    ) -> GenerationSchema? {
        guard let root = Self.root(of: inputSchema) else { return nil }
        return try? GenerationSchema(
            root: object(root, name: name, description: description, detail: detail), dependencies: [])
    }

    private static func root(of bytes: [UInt8]) -> JSON? {
        guard let document = try? AemiJSON.parse(bytes), document.root.isObject else { return nil }
        return document.root
    }

    private static func object(_ schema: JSON, name: String, description: String?, detail: Detail)
        -> DynamicGenerationSchema
    {
        let required = Set(schema["required"].array?.compactMap(\.string) ?? [])
        let properties = schema["properties"].object ?? [:]
        let kept = properties.keys.sorted()
            .compactMap { key -> DynamicGenerationSchema.Property? in
                guard let property = properties[key], property.isObject else { return nil }
                return DynamicGenerationSchema.Property(
                    name: key, description: clipped(property["description"].string, limit: detail.limit),
                    schema: value(property, name: name + "." + key, detail: detail), isOptional: !required.contains(key)
                )
            }
        return DynamicGenerationSchema(
            name: name, description: clipped(description, limit: detail.limit), properties: kept)
    }

    private static func value(_ schema: JSON, name: String, detail: Detail) -> DynamicGenerationSchema {
        if let choices = schema["enum"].array?.compactMap(\.string), !choices.isEmpty,
            choices.count == schema["enum"].count
        {
            return DynamicGenerationSchema(name: name, anyOf: choices)
        }
        switch Self.kind(of: schema) {
            case "integer": return DynamicGenerationSchema(type: Int.self)
            case "number": return DynamicGenerationSchema(type: Double.self)
            case "boolean": return DynamicGenerationSchema(type: Bool.self)
            case "array":
                let items = schema["items"]
                return DynamicGenerationSchema(
                    arrayOf: items.isObject
                        ? value(items, name: name + "[]", detail: detail) : DynamicGenerationSchema(type: String.self))
            case "object": return object(schema, name: name, description: nil, detail: detail)
            default: return DynamicGenerationSchema(type: String.self)
        }
    }

    /// The schema's type, taking the first non-null one of a union.
    private static func kind(of schema: JSON) -> String? {
        if let single = schema["type"].string { return single }
        return schema["type"].array?.compactMap(\.string).first { $0 != "null" }
    }

    /// A description at the length the window allows: with a brief limit its first sentence, with a full one every sentence; cut at `limit` either way.
    static func clipped(_ text: String?, limit: Int = Detail.brief.limit) -> String? {
        guard let text, !text.isEmpty else { return nil }
        let kept =
            limit <= Detail.brief.limit
            ? (text.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? text)
            : text
        return kept.count <= limit ? kept : String(kept.prefix(limit - 1)) + "…"
    }
}

extension AppleToolSchema {
    /// How many characters the tool costs the window: its name, its description and what it says of each argument, at `detail`.
    static func footprint(of definition: ToolDefinition, detail: Detail = .full) -> Int {
        let base = definition.name.count + (clipped(definition.description, limit: detail.limit)?.count ?? 0)
        guard let root = root(of: definition.inputSchema.bytes) else { return base }
        return base + footprint(of: root, detail: detail)
    }

    private static func footprint(of schema: JSON, detail: Detail) -> Int {
        (schema["properties"].object ?? [:])
            .reduce(0) { total, entry in
                total + entry.key.count + (clipped(entry.value["description"].string, limit: detail.limit)?.count ?? 0)
                    + 16 + footprint(of: entry.value, detail: detail)
            }
    }
}
