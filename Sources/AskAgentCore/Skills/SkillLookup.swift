/// The answer to "load the skill called this".
public enum SkillLookup: Sendable, Equatable {
    case found(Skill)
    /// The skill exists but asked not to be loaded by the model on its own.
    case onlyWhenAsked(Skill)
    /// No such skill; the names nearest to what was asked, to help the next call.
    case missing(suggestions: [String])
}
