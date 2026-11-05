/// An agent definition (roadmap 0063 phase 3, ADR-0146): who a subagent is told it is, which of the subagent's tools it keeps, and
/// which model it would rather use.
public struct AgentDefinition: Sendable, Equatable {
    public let name: String
    public let description: String
    /// What the subagent is told before its task.
    public let instructions: String
    /// The tools it keeps, as written; none named narrows nothing. A name ask does not know grants nothing.
    public let tools: [ToolReference]
    public let models: ModelPreference
    public let file: String
    /// The file's path with links resolved, which trust is kept under; `file` when it was read from text.
    public var realFile: String = ""
    /// The SHA-256 of the file's bytes, which a project's definition is trusted as (roadmap 0063 phase 3).
    public var digest: String = ""
    public let diagnostics: [String]

    /// The definition in `text`, the file at `file`; nil when it gives neither a description nor a body to take one from.
    public static func read(file: String, text: String) -> AgentDefinition? {
        let head = DefinitionFile(parsing: text)
        let instructions = head.body.trimmingWhitespace()
        guard let description = head.text("description") ?? SkillDiscovery.derivedDescription(instructions) else {
            return nil
        }
        let fileName = String(file.split(separator: "/").last ?? "")
        let name = head.text("name") ?? String(fileName.hasSuffix(".md") ? fileName.dropLast(3) : fileName[...])
        let tools = ToolReference.parse(head.value("tools"))
        let unknown = tools.filter { $0.ask == nil }.map(\.token)
        var diagnostics = head.diagnostics
        if !unknown.isEmpty {
            diagnostics.append("tools ask does not know (kept, and grant nothing): \(unknown.joined(separator: ", "))")
        }
        return AgentDefinition(
            name: name,
            description: description,
            instructions: instructions,
            tools: tools,
            models: ModelPreference(head),
            file: file,
            diagnostics: diagnostics
        )
    }
}
