/// What one run has seen of its context window, and the rules that stop it looping on a window it cannot fit.
///
/// A refusal for length is compacted and sent again once; a refusal right after compacting means the conversation
/// cannot be made short enough. A reply cut off by a full window is compacted and continued, at most
/// ``AgentLoop/fullWindowCompactionsBeforeGivingUp`` times in a row (diary 14 measured the loop this prevents).
struct WindowWatch {
    /// Whether the last reply stopped because the window filled, so the next request must be compacted first.
    private(set) var contextFull = false
    private var compactedForOverflow = false
    private var fullInARow = 0

    /// A request was refused for its length.
    /// - Throws: ``AgentError/contextOverflow(_:)`` when the previous request was already a compacted retry.
    mutating func overflowed(_ reason: String) throws(AgentError) {
        guard !compactedForOverflow else { throw .contextOverflow(reason) }
        compactedForOverflow = true
    }

    /// A request was answered.
    mutating func responded() { compactedForOverflow = false }

    /// The answer did or did not fill the window.
    /// - Throws: ``AgentError/contextOverflow(_:)`` once the window filled too many times in a row.
    mutating func observe(filled: Bool) throws(AgentError) {
        contextFull = filled
        fullInARow = filled ? fullInARow + 1 : 0
        guard fullInARow <= AgentLoop.fullWindowCompactionsBeforeGivingUp else {
            throw .contextOverflow("the context window filled again after compacting \(fullInARow - 1) times in a row")
        }
    }
}
