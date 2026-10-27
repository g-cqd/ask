internal import TerminalKitText

extension Transcript {
    /// Project only expanded tool input. Its fold store is separate from the whole-tool fold store.
    func shownToolInput(at index: Int) -> ShownToolInput? {
        guard !isFolded(index), case .tool(_, _, _, _, let input) = items[index], !input.isEmpty else { return nil }
        return ShownToolInput(input) { ordinal in
            codeFolds.isFolded(CodeBlockID(item: index, fence: ordinal), default: codeFoldedByDefault)
        }
    }
}
