internal import TerminalKitText

/// Long code blocks in assistant messages fold to a placeholder line (ADR-0046: `ui.codeFoldLines`), each one on its own, like tool
/// output and thinking. The message stays one item: a fold changes what it shows, not how many items there are.
extension Transcript {
    /// What the assistant item at `index` shows, folded blocks replaced by their placeholders. Nil for any other item.
    func shownCode(at index: Int) -> ShownCode? {
        guard case .assistant(let text) = items[index] else { return nil }
        return ShownCode(text, longerThan: codeFoldLines) { fence in
            codeFolds.isFolded(CodeBlockID(item: index, fence: fence), default: codeFoldedByDefault)
        }
    }

    /// The long code block a click on display hard line `line` of item `index` toggles, or nil when that line toggles nothing.
    func codeFence(toggledByLine line: Int, at index: Int) -> Int? {
        guard items.indices.contains(index) else { return nil }
        return shownCode(at: index)?.toggles[line]
    }

    /// Opens or closes one long code block.
    mutating func toggleCodeFold(_ fence: Int, at index: Int) {
        codeFolds.toggle(CodeBlockID(item: index, fence: fence), default: codeFoldedByDefault)
        revisions[index] = bump()
    }

    /// Sets what long code blocks do until the user chooses, and forgets every choice so it reaches them all.
    public mutating func setCodeFoldedByDefault(_ folded: Bool) {
        codeFoldedByDefault = folded
        codeFolds.clearChoices()
        relayOutCode()
    }

    /// Sets the length above which a code block folds. A change lays out again only the messages that hold a fence.
    public mutating func setCodeFoldLines(_ lines: Int) {
        let lines = Swift.max(1, lines)
        guard lines != codeFoldLines else { return }
        codeFoldLines = lines
        relayOutCode()
    }

    private mutating func relayOutCode() {
        for index in items.indices {
            guard case .assistant(let text) = items[index], ShownCode.mayContainFence(text) else { continue }
            revisions[index] = bump()
        }
    }
}
