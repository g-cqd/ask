/// Collects the properties declared in a tool's input.
@resultBuilder
public enum ToolSchemaBuilder {
    public static func buildBlock(_ properties: ToolProperty...) -> [ToolProperty] { properties }
}
