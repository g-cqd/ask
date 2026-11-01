/// What a planned call changed, and what was already so (ADR-0141), said in one line with ids as runs.
public struct TaskReport: Sendable, Equatable {
    public var added: [Int] = []
    public var edited: [Int] = []
    public var states: [TaskState: [Int]] = [:]
    public var moved: [Int] = []
    public var linked: [Int] = []
    public var unlinked: [Int] = []
    public var removed: [Int] = []
    public var already: [Int] = []

    public init() {}

    /// `added t182–t185 (4) · done t53–t181 (129) · already so: t12`.
    public var summary: String {
        var parts: [String] = []
        let named: [(String, [Int])] =
            [("added", added), ("edited", edited)]
            + TaskState.allCases.map { (Self.word($0), states[$0] ?? []) }
            + [("moved", moved), ("linked", linked), ("unlinked", unlinked), ("removed", removed)]
        for (word, ids) in named where !ids.isEmpty { parts.append(ListRef.counted(word, ids, prefix: "t")) }
        if !already.isEmpty { parts.append(ListRef.counted("already so:", already, prefix: "t")) }
        return parts.isEmpty ? "Nothing to change." : parts.joined(separator: " · ")
    }

    static func word(_ state: TaskState) -> String { state == .inProgress ? "in progress" : state.rawValue }
}
