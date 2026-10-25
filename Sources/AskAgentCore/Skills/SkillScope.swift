/// Where a skill came from, by whose it is.
public enum SkillScope: String, Sendable, Equatable {
    /// The user's own: their home directory's skill locations.
    case user
    /// A project's: a skill directory in the working directory or an ancestor up to the repository root. Loaded only for a trusted project (roadmap 0061).
    case project
    /// Shipped inside a tool: not the user's, and changing with that tool's updates.
    case bundled
}
