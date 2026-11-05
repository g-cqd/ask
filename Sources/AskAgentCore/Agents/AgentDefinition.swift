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
        let isTOML = file.lowercased().hasSuffix(".toml")
        let head = DefinitionFile(parsing: text, isTOML: isTOML)
        // Codex keeps the instructions in a field; Markdown files keep them in the body.
        let written = head.text("developer_instructions", "instructions", "prompt") ?? head.body
        let instructions = written.trimmingWhitespace()
        guard let description = head.text("description") ?? SkillDiscovery.derivedDescription(instructions) else {
            return nil
        }
        let fileName = String(file.split(separator: "/").last ?? "")
        let name = head.text("name") ?? Self.name(ofFile: fileName)
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

    /// A file's name without what marks it a definition: `.agent.md` (Copilot), `.md`, `.toml` (Codex).
    static func name(ofFile fileName: String) -> String {
        for suffix in [".agent.md", ".md", ".toml"] where fileName.lowercased().hasSuffix(suffix) {
            return String(fileName.dropLast(suffix.count))
        }
        return fileName
    }
}
