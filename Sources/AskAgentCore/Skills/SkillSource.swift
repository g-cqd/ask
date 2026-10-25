/// A harness whose skill directories ask reads, with the directories. The rows are in the composition root (`Sources/ask/SkillSource+Harnesses.swift`), where
/// the names of other tools belong; this is the shape of a row.
public struct SkillSource: Sendable, Equatable {
    public let id: String
    /// Under the home directory.
    public let userRoots: [String]
    /// Under the project directory, and each ancestor of it up to the repository root.
    public let projectRoots: [String]
    /// Under the home directory: skills the tool ships.
    public let bundledRoots: [String]

    public init(id: String, userRoots: [String], projectRoots: [String], bundledRoots: [String]) {
        self.id = id
        self.userRoots = userRoots
        self.projectRoots = projectRoots
        self.bundledRoots = bundledRoots
    }

    /// The id that selects bundled skills (`from`, `--from`).
    public static let bundledID = "bundled"
}
