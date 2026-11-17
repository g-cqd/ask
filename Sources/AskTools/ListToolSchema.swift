internal import AskAI
internal import AskAgentCore

/// What `tasks` and `notes` share of their input (ADR-0141): two lists of one store, told to a model in the same words, so what is
/// learnt of one holds for the other.
enum ListToolSchema {
    /// A list tool: changes made in order, and a read after them.
    /// - Parameters:
    ///   - name: the tool's name.
    ///   - description: what the model is told the tool is for.
    ///   - change: the fields of one change.
    ///   - changes: what the model is told `changes` is.
    ///   - read: the fields of a read, from ``read(views:view:noun:)``.
    /// - Returns: the tool's definition.
    static func definition(
        name: String,
        description: String,
        change: [ToolSchema.Field],
        changes: String,
        read: [ToolSchema.Field]
    ) -> ToolDefinition {
        ToolDefinition(
            name: name,
            description: description,
            fields: [
                .init("changes", .array(.object(change)), changes),
                .init("read", .object(read), "What to show, after any changes.")
            ]
        )
    }

    /// What a read takes: which entries, some in full, those some words match, and how many.
    /// - Parameters:
    ///   - views: the views there are.
    ///   - view: what the model is told of them.
    ///   - noun: what the entries are called, in the plural.
    /// - Returns: the fields of a read.
    static func read(views: [String], view: String, noun: String) -> [ToolSchema.Field] {
        [
            .init("view", .choice(views), view),
            .init("ids", .string(), "These \(noun) in full."),
            .init("text", .string(), "Only \(noun) matching these words."),
            .init("limit", .integer(), "At most this many: \(ListLimits.defaultReadLimit) unless given.")
        ]
    }
}
