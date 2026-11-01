internal import AemiJSON

extension ToolDefinition {
    /// A tool whose input is the object `fields` describe (ADR-0141); the decoder, not the schema, refuses other fields, to keep it lean.
    public init(name: String, description: String, fields: [ToolSchema.Field], required: [String] = []) {
        var writer = JSONStreamWriter(capacity: 512)
        writer.object { writer in ToolSchema.writeObject(fields, required, false, into: &writer) }
        self.init(name: name, description: description, inputSchema: JSONObject(unchecked: writer.finish()))
    }
}
