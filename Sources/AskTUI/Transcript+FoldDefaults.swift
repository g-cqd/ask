internal import TerminalKitText

/// What blocks of each kind do until the person chooses (`ui.fold`).
extension Transcript {
    /// Sets what tool blocks do until the user chooses, and forgets the choices made for tool blocks so it reaches every one.
    public mutating func setToolsFoldedByDefault(_ folded: Bool) {
        toolsFoldedByDefault = folded
        forgetChoices { if case .thinking = $0 { false } else { true } }
    }

    /// Sets what thinking blocks do until the user chooses, and forgets the choices made for them.
    public mutating func setThinkingFoldedByDefault(_ folded: Bool) {
        thinkingFoldedByDefault = folded
        forgetChoices { if case .thinking = $0 { true } else { false } }
    }

    /// Forgets the choices for the items `matches` accepts but summaries (theirs is their own), and has them laid out again.
    private mutating func forgetChoices(where matches: (Item) -> Bool) {
        for index in items.indices where matches(items[index]) && !summaryBlocks.contains(index) {
            folds.clearChoice(for: index)
            revisions[index] = bump()
        }
    }
}
