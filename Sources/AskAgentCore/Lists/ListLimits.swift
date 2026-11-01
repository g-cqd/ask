/// What a list and a call to its tool may hold (ADR-0141). The schema states them; the planner enforces them.
public enum ListLimits {
    public static let changesPerCall = 100
    /// Ids one call resolves, ranges expanded.
    public static let idsPerCall = 1000
    public static let entries = 2000
    public static let titleLength = 120
    public static let detailLength = 4000
    public static let tagsPerTask = 8
    public static let nameLength = 24
    public static let readLimit = 200
    public static let defaultReadLimit = 50
    public static let textLength = 80
    /// An idea's line in a listing; `full` shows it whole.
    public static let ideaLineLength = 120

    /// A tag or a `ref`: `[a-z0-9-]{1,24}`.
    public static func isName(_ text: String) -> Bool {
        !text.isEmpty && text.count <= nameLength
            && text.unicodeScalars.allSatisfy { ("a" ... "z").contains($0) || ("0" ... "9").contains($0) || $0 == "-" }
    }
}
