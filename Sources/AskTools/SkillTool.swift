public import AskAI
public import AskAgentCore
internal import Foundation

/// `skill`: a skill's full instructions, by name (roadmap 0061).
///
/// The model sees each skill's name, description and path in its instructions and loads the body here when a task matches. The result is an ordinary
/// tool result, so a resumed session replays it and no session record had to change. The tool takes **no path**: a name finds a skill the discovery
/// already found in a harness's directory, and `from` can only narrow to harnesses, never name a place. A skill grants no permission.
public struct SkillTool: ArgumentTool {
    /// `from` as a model writes it: a string of words, or a list of them.
    public struct Words: Decodable, Sendable {
        let list: [String]

        public init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let one = try? container.decode(String.self) {
                list = one.split(whereSeparator: { $0 == "," || $0.isWhitespace }).map(String.init)
            } else {
                list = try container.decode([String].self)
            }
        }
    }

    public struct Arguments: Decodable, Sendable {
        let name: String
        let from: Words?
    }

    public let definition = ToolDefinition(
        name: "skill",
        description:
            "Load a skill's full instructions by name, from the list in your instructions. Pass from to narrow where it is looked for: harness ids, "
            + "separated by commas, or user or bundled; it cannot name a path."
    ) {
        ToolProperty.string("name", minLength: 1)
        ToolProperty.string("from").optional
    }

    private let catalog: SkillCatalog
    private let knownSources: [String]

    /// - Parameters:
    ///   - catalog: the skills found, which this tool serves and never adds to.
    ///   - knownSources: the harness ids that exist, so a word in `from` can be told from a mistake.
    public init(catalog: SkillCatalog, knownSources: [String]) {
        self.catalog = catalog
        self.knownSources = knownSources
    }

    public func run(_ arguments: Arguments, in context: ToolContext) async throws(ToolFailure) -> ToolOutput {
        let selection = SkillSelection(tokens: arguments.from?.list ?? [], knownSources: knownSources)
        switch catalog.find(arguments.name, selection: selection) {
            case .found(let skill):
                return load(skill, unknownWords: selection.unknown)
            case .onlyWhenAsked(let skill):
                return .error("The skill \"\(skill.name)\" is only loaded when the user asks for it.")
            case .missing(let suggestions):
                let hint =
                    suggestions.isEmpty
                    ? "No skills are available." : "Available: \(suggestions.joined(separator: ", "))."
                let words =
                    selection.unknown.isEmpty
                    ? "" : " Not a harness or a scope, so ignored: \(selection.unknown.joined(separator: ", "))."
                return .error("No skill is called \"\(arguments.name)\". \(hint)\(words)")
        }
    }

    private func load(_ skill: Skill, unknownWords: [String]) -> ToolOutput {
        let note = unknownWords.isEmpty ? nil : "Ignored in from: \(unknownWords.joined(separator: ", "))"
        do {
            return ToolOutput(try SkillContents.load(skill, note: note))
        } catch {
            return .error(error.reason)
        }
    }
}
