/// A session's prompts as numbered turns, for going back to before one (`/tree`, ADR-0093).
///
/// A session is a tree: going back and sending something else adds a branch and removes nothing. The outline lists the prompts, the
/// only entries a person wrote, in the order they were recorded, which never changes, so a number read in a listing still means that
/// prompt when it is used, whatever was added since.
public struct SessionOutline: Sendable, Equatable {
    /// Where a prompt sits among those that followed the same point.
    public enum Follows: Sendable, Equatable {
        /// The first prompt sent from that point: the trunk.
        case first
        /// A later one, sent after going back: a branch. `after` is the number of the prompt whose reply it follows, or nil when it
        /// started again from nothing.
        case branch(after: Int?)
    }

    /// One prompt.
    public struct Turn: Sendable, Equatable {
        /// 1, 2, 3, in the order recorded.
        public let number: Int
        /// The prompt's own entry.
        public let entry: EntryID
        /// The entry it follows: where the session's leaf goes to put this prompt, and what follows it, back to be written. Nil for a
        /// prompt that starts from nothing.
        public let before: EntryID?
        /// What was written, whole.
        public let text: String
        /// Whether the prompt is on the path from the first entry to the one the session is at now.
        public let isOnActiveBranch: Bool
        /// Whether it is the trunk or a branch.
        public let follows: Follows
    }

    /// Every prompt, in the order recorded.
    public let turns: [Turn]

    /// The outline of `tree`.
    /// - Complexity: O(entries × depth) for the branch point lookups.
    public init(_ tree: SessionTree) {
        let onPath = Set(tree.activeBranch().map(\.id))
        var numbers: [EntryID: Int] = [:]
        var firstAfter: [EntryID?: EntryID] = [:]
        var built: [Turn] = []
        for entry in tree.entries {
            guard case .user(let text) = entry.payload else { continue }
            let number = built.count + 1
            numbers[entry.id] = number
            let follows: Follows
            if firstAfter[entry.parentID] == nil {
                firstAfter[entry.parentID] = entry.id
                follows = .first
            } else {
                follows = .branch(after: Self.promptNumber(before: entry.parentID, in: tree, numbers: numbers))
            }
            built.append(
                Turn(
                    number: number, entry: entry.id, before: entry.parentID, text: SkillInvocation.shown(text),
                    isOnActiveBranch: onPath.contains(entry.id), follows: follows))
        }
        turns = built
    }

    /// The turn numbered `number`, or nil.
    public func turn(_ number: Int) -> Turn? { turns.indices.contains(number - 1) ? turns[number - 1] : nil }

    /// One line a turn, for showing: a mark for the path, the number, the first line of the prompt cut to `textLimit`, and, for a
    /// branch, what it follows.
    /// - Parameter textLimit: the most characters of the prompt's first line.
    /// - Returns: the lines, in turn order; none for a session with no prompts.
    public func lines(textLimit: Int = 60) -> [String] {
        let width = String(turns.count).count
        return turns.map { turn in
            let shown = Self.oneLine(turn.text, limit: textLimit)
            let number = String(turn.number)
            let padded = String(repeating: " ", count: width - number.count) + number
            let branch: String
            switch turn.follows {
                case .first: branch = ""
                case .branch(let after?): branch = "  (branch after \(after))"
                case .branch(nil): branch = "  (starts again)"
            }
            return (turn.isOnActiveBranch ? "> " : "  ") + padded + "  " + shown + branch
        }
    }

    /// `text` on one line, cut to `limit` characters with an ellipsis.
    public static func oneLine(_ text: String, limit: Int) -> String {
        let flat = text.split(whereSeparator: \.isNewline).joined(separator: " ")
        return flat.count <= limit ? flat : String(flat.prefix(limit - 1)) + "…"
    }

    /// The number of the nearest prompt at or before `entry`, or nil when there is none.
    private static func promptNumber(before entry: EntryID?, in tree: SessionTree, numbers: [EntryID: Int]) -> Int? {
        var cursor = entry
        while let current = cursor, let found = tree.entry(current) {
            if let number = numbers[current] { return number }
            cursor = found.parentID
        }
        return nil
    }
}
