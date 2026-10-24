/// The files of a project, as the `@` picker offers them (roadmap 0048, ADR-0069).
public struct ProjectListing: Sendable, Equatable {
    /// Paths relative to the project directory, sorted, only files ask may read.
    public var paths: [String]
    /// How many files were left out because the sandbox does not let ask read them. Their names are not offered either.
    public var hidden: Int
    /// Whether the listing stopped at its limit.
    public var truncated: Bool

    public init(paths: [String] = [], hidden: Int = 0, truncated: Bool = false) {
        self.paths = paths
        self.hidden = hidden
        self.truncated = truncated
    }
}
