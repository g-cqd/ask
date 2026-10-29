internal import TerminalKitText

/// Long code blocks in assistant messages fold to a placeholder line (ADR-0046: `ui.codeFoldLines`), each one on its own, like tool
/// output and thinking. The message stays one item: a fold changes what it shows, not how many items there are.
extension Transcript {
    /// What the assistant item at `index` shows, folded blocks replaced by their placeholders. Nil for any other item.
    /// Drawn as Markdown, a message shows its text as written, so there is none: code folds are drawn by ``markdownFences(at:)``.
    func shownCode(at index: Int) -> ShownCode? {
        guard !markdown, case .assistant(let text) = items[index] else { return nil }
        return ShownCode(text, longerThan: codeFoldLines) { fence in
            codeFolds.isFolded(CodeBlockID(item: index, fence: fence), default: codeFoldedByDefault)
        }
    }

    /// The long code block a click on display hard line `line` of item `index` toggles, or nil when that line toggles nothing.
    func codeFence(toggledByLine line: Int, at index: Int) -> Int? {
        guard items.indices.contains(index) else { return nil }
        return shownToolInput(at: index)?.toggles[line - (commandBlocks.contains(index) ? 0 : 1)]
            ?? shownCode(at: index)?.toggles[line]
            ?? markdownFences(at: index)?.first { $0.fence.openingLine == line }?.ordinal
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

    /// Draws assistant messages as Markdown, or as the text the model wrote. Every assistant message is laid out again.
    public mutating func setMarkdown(_ on: Bool) {
        guard on != markdown else { return }
        markdown = on
        for index in items.indices {
            if case .assistant = items[index] { revisions[index] = bump() }
        }
    }

    /// The long code blocks of the assistant message at `index` drawn as Markdown, each with its ordinal among the message's fences and whether
    /// it is folded. Nil when the item is not such a message.
    func markdownFences(at index: Int) -> [(fence: CodeFence, ordinal: Int, folded: Bool)]? {
        guard markdown, case .assistant(let text) = items[index], ShownCode.mayContainFence(text) else { return nil }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        return CodeFence.scan(lines).enumerated()
            .filter { $0.element.bodyLines > codeFoldLines }
            .map { ordinal, fence in
                (
                    fence, ordinal,
                    codeFolds.isFolded(CodeBlockID(item: index, fence: ordinal), default: codeFoldedByDefault)
                )
            }
    }

    private mutating func relayOutCode() {
        for index in items.indices {
            switch items[index] {
                case .assistant(let text) where ShownCode.mayContainFence(text): revisions[index] = bump()
                case .tool(_, _, _, _, let input) where input.contains("<<"): revisions[index] = bump()
                default: continue
            }
        }
    }
}
