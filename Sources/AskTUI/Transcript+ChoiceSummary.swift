/// What a choice put in force, said once (note n28): a model chosen and then its thinking level leave one block, the newest summary,
/// instead of a line and a notice for each.
extension Transcript {
    /// Shows `text` as the summary of a choice: in place of the summary just shown when nothing came after it, else as a new block.
    mutating func addChoiceSummary(_ text: String) {
        if let index = choiceSummaryAt, index == items.count - 1, case .notice = items[index] {
            items[index] = .notice(text, isError: false)
            revisions[index] = bump()
            return
        }
        append(.notice(text, isError: false))
        choiceSummaryAt = items.count - 1
    }
}
