/// What discovery found: the skills that load, the ones that lost a name to another, and where it looked.
public struct SkillCatalog: Sendable, Equatable {
    /// One place that was searched, whether or not it exists.
    public struct Root: Sendable, Equatable {
        public let path: String
        public let source: String
        public let scope: SkillScope
        public let exists: Bool
    }

    /// The skills that win their names, in the order of precedence: the nearest project first, then the user's, in the order of `SkillSource.all`.
    public internal(set) var skills: [Skill] = []
    /// Skills with a name another skill already has, and different content: reachable by choosing their source, never offered alongside.
    public internal(set) var shadowed: [Skill] = []
    /// Files that were looked at and not made into skills, each with the reason.
    public internal(set) var skipped: [String] = []
    public internal(set) var roots: [Root] = []

    /// A catalog with nothing in it.
    public init() {}

    /// The skills by name, as the advertisement lists them: a stable order that does not change with what is found first.
    public var byName: [Skill] { skills.sorted { $0.name.lowercased() < $1.name.lowercased() } }

    /// A rough count of what advertising every skill costs, in tokens: characters divided by four. An estimate, not a tokenizer's number.
    public var estimatedAdvertisementTokens: Int {
        skills.filter(\.modelInvocable).reduce(0) { $0 + $1.advertisement.count + 1 } / 4
    }
}
