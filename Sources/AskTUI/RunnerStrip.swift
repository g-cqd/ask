internal import TerminalKitStyle

/// The strip's rows as drawn, and which runner each row is, so the frame can tell a click what it landed on.
struct RunnerStrip {
    var lines: [ScreenComposer.Line] = []
    var ids: [String] = []

    /// - Parameters:
    ///   - state: what the screen holds: the tree, the collapsed parents and the selection.
    ///   - available: the most rows it may take.
    ///   - columns: the width it is drawn in, which bounds the indentation.
    ///   - limit: the most rows it draws; the strip takes five, the sidebar every row it has.
    ///   - requiresOpen: whether the strip's own open state decides; the sidebar has its own.
    init(_ state: ScreenState, available: Int, columns: Int, capacity limit: Int = 5, requiresOpen: Bool = true) {
        guard state.runnersOpen || !requiresOpen, !state.runners.isEmpty, available > 0 else { return }
        let rows = state.runnerTree.visible(collapsed: state.collapsedRunners)
        let capacity = Swift.min(limit, available)
        let shown = rows.count > capacity ? capacity - 1 : rows.count
        // The selected row stays in the window.
        let selected = rows.firstIndex { $0.row.runner.id == state.stripSelection }
        let first = selected.map { Swift.max(0, Swift.min($0 - shown + 1, rows.count - shown)) } ?? 0
        for item in rows[first ..< first + shown] {
            let runner = item.row.runner
            let indent = String(repeating: "  ", count: Swift.min(item.row.depth, Swift.max(0, columns / 2)))
            var text =
                indent + runner.name + "  " + runner.detail.replacing("\n", with: " ") + " · " + runner.state.rawValue
            if item.hidden > 0 { text += " · \(item.hidden) hidden" }
            let chosen = runner.id == state.stripSelection
            lines.append(ScreenComposer.Line(text: text, style: chosen ? Style(bold: true) : Style(dim: true)))
            ids.append(runner.id)
        }
        if shown < rows.count {
            lines.append(ScreenComposer.Line(text: "… \(rows.count - shown) more", style: Style(dim: true)))
        }
    }
}
