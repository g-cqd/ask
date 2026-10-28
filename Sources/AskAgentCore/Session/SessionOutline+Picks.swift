extension SessionOutline {
    /// One prompt as a row of the `/tree` picker (roadmap 0093).
    public struct Pick: Sendable, Equatable {
        /// What `/tree` takes to go back to before this prompt.
        public let number: Int
        /// The first line of the prompt, cut.
        public let text: String
        /// Whether the prompt is on the path the session is at now.
        public let isOnActiveBranch: Bool
        /// Where a branch comes from (`branch after 2`, `starts again`), empty for the trunk.
        public let note: String
    }

    /// The prompts as picker rows, newest first: going back usually means going back a little.
    /// - Parameter textLimit: the most characters of a prompt's first line.
    /// - Returns: a row for every prompt, the last recorded first; none for a session with no prompts.
    public func picks(textLimit: Int = 80) -> [Pick] {
        turns.reversed()
            .map { turn in
                let note =
                    switch turn.follows {
                        case .first: ""
                        case .branch(let after?): "branch after \(after)"
                        case .branch(nil): "starts again"
                    }
                return Pick(
                    number: turn.number, text: Self.oneLine(turn.text, limit: textLimit),
                    isOnActiveBranch: turn.isOnActiveBranch, note: note)
            }
    }
}
