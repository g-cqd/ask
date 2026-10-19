internal import AemiJSON

extension ToolDefinition {
    /// A tool whose input is an object with these properties.
    ///
    /// ```swift
    /// ToolDefinition(name: "read", description: "Read a file.") {
    ///     ToolProperty.string("path")
    ///     ToolProperty.integer("offset", minimum: 1).optional
    /// }
    /// ```
    public init(name: String, description: String, @ToolSchemaBuilder properties: () -> [ToolProperty]) {
        let declared = properties()
        var writer = JSONStreamWriter(capacity: 256)
        writer.object { writer in
            writer.field("type", "object")
            writer.key("properties")
            writer.object { writer in
                for property in declared {
                    writer.key(property.name)
                    property.writeSchema(into: &writer)
                }
            }
            let required = declared.filter(\.isRequired)
            if !required.isEmpty {
                writer.key("required")
                writer.array { writer in
                    for property in required { writer.string(property.name) }
                }
            }
        }
        self.init(name: name, description: description, inputSchema: JSONObject(unchecked: writer.finish()))
    }
}
