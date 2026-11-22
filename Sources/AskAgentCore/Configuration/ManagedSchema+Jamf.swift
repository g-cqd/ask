internal import AemiJSON

extension ManagedSchema {
    /// The schema Jamf Pro takes for a custom application's settings (its "Application & Custom Settings" payload, a JSON Schema with
    /// `property_order` and `options.infoText`), for the domain `studio.aemi.ask`.
    public static func jamf() throws -> [UInt8] {
        var properties = OrderedDictionary<String, JSONValue>()
        var order = 0
        for (kind, keys) in try documents() {
            order += 1
            let summary =
                kind == .requirements
                ? "Applied after every other setting: nothing a person sets changes them."
                : "Where a person starts: their own settings change them."
            properties[kind.rawValue] = object(
                title: kind == .requirements ? "Requirements" : "Defaults",
                description: summary,
                order: order,
                properties: tree(keys)
            )
        }
        let schema: OrderedDictionary<String, JSONValue> = [
            "title": .string("ask (\(ManagedProfile.domain))"),
            "description": .string(
                "Settings for ask, the terminal coding agent. Each key is the one config.json takes; see ask's docs/configuration.md."
            ),
            "properties": .object(properties)
        ]
        do { return try JSONValue.object(schema).encodedBytes(options: JSONEncodingOptions(prettyPrinted: true)) } catch
        {
            preconditionFailure("a schema built of JSON values encodes: \(error)")
        }
    }

    /// `keys` nested by their paths, each level in the order its first key comes.
    private static func tree(_ keys: [Key]) -> OrderedDictionary<String, JSONValue> {
        var groups = OrderedDictionary<String, [Key]>()
        var leaves = OrderedDictionary<String, Key>()
        for key in keys {
            if key.path.count == 1 { leaves[key.path[0]] = key } else { groups[key.path[0], default: []].append(key) }
        }
        var result = OrderedDictionary<String, JSONValue>()
        var order = 0
        for key in keys {
            let name = key.path[0]
            guard result[name] == nil else { continue }
            order += 1
            if let leaf = leaves[name] {
                result[name] = property(leaf, order: order)
            } else if let group = groups[name] {
                let inner = group.map { Key(dropping: $0) }
                result[name] = object(title: name, description: "", order: order, properties: tree(inner))
            }
        }
        return result
    }

    private static func object(
        title: String,
        description: String,
        order: Int,
        properties: OrderedDictionary<String, JSONValue>
    ) -> JSONValue {
        var object: OrderedDictionary<String, JSONValue> = ["title": .string(title)]
        if !description.isEmpty { object["description"] = .string(description) }
        object["property_order"] = .int(Int64(order * 5))
        object["type"] = .string("object")
        object["properties"] = .object(properties)
        return .object(object)
    }

    private static func property(_ key: Key, order: Int) -> JSONValue {
        var property: OrderedDictionary<String, JSONValue> = [
            "title": .string(key.title),
            "description": .string(key.help + nullNote(key)),
            "property_order": .int(Int64(order * 5)),
            "type": profileTypes(key).count == 1
                ? .string(profileTypes(key)[0].rawValue) : .array(profileTypes(key).map { .string($0.rawValue) })
        ]
        if let value = key.defaultValue { property["default"] = value }
        if !key.choices.isEmpty { property["enum"] = .array(key.choices.map(JSONValue.string)) }
        if key.types.contains(.array) {
            // A list of words or paths, or, where the example's entries are objects (modelScopes, openers.rules), of objects.
            let holdsObjects =
                if case .array(let items) = key.example, case .object = items.first { true } else { false }
            property["items"] = .object(["type": .string(holdsObjects ? "object" : "string")])
        }
        property["options"] = .object(["infoText": .string("Key: \(key.title). Example: \(key.exampleText)")])
        return .object(property)
    }
}

extension ManagedSchema.Key {
    /// `key` one level down: its path without its first name.
    init(dropping key: Self) {
        self.init(
            path: Array(key.path.dropFirst()),
            title: key.title,
            help: key.help,
            types: key.types,
            choices: key.choices,
            example: key.example,
            defaultValue: key.defaultValue
        )
    }

    /// The example as a person types it in `config.json`.
    var exampleText: String {
        (try? example.encodedBytes(options: JSONEncodingOptions())).map { String(decoding: $0, as: UTF8.self) } ?? ""
    }
}
