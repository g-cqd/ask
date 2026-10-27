/// A skill found on disk, read permissively. Everything in it is what a file said; nothing is a promise about what the skill does.
public struct Skill: Sendable, Equatable {
    public let name: String
    public let description: String
    /// The skill file where it was found (possibly through a symlink).
    public let file: String
    /// The skill file with every symlink resolved: what two paths to one skill have in common.
    public let realFile: String
    /// The directory the skill's bundled files are relative to.
    public let directory: String
    public let source: String
    public let scope: SkillScope
    /// False when the skill asked not to be offered to the model on its own (`disable-model-invocation`); the user can still invoke it.
    public let modelInvocable: Bool
    /// The tools it names (`allowed-tools`, `tools`), as written and as ask reads them. Shown, never honoured: a skill grants nothing.
    public let tools: [ToolReference]
    public let disallowedTools: [ToolReference]
    /// The models it prefers, if it says (Claude's skills may).
    public let models: ModelPreference
    /// The other keys its head carries, as written.
    public let otherKeys: [String]
    /// What was noticed and tolerated while reading it.
    public let diagnostics: [String]
    /// The SHA-256 of the file's bytes, so two copies of one skill are one.
    public let digest: String

    /// The most characters of a description the model is told in initial prompt advertisement.
    public static let advertisedDescriptionLimit = 80

    /// What the system prompt says about it: its name, what it is for, and where it is.
    public var advertisement: String {
        let text =
            description.count > Self.advertisedDescriptionLimit
            ? String(description.prefix(Self.advertisedDescriptionLimit - 1)) + "…" : description
        return "- \(name): \(text) (\(file))"
    }
}
