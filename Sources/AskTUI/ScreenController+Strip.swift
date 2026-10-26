internal import TerminalKitCodecs
internal import TerminalKitInput

/// The runner strip as keys use it (roadmap 0062, step 2): Down from an empty or finished draft enters it; Up and Down move; Right and Left open and close a
/// parent; Enter focuses the runner; Esc goes back one step. Every click has one of these keys (ADR-0044).
extension ScreenController {
    /// The keys of the strip, or nil when the key is the editor's. Any other key hands the keys back to the input and is typed there.
    mutating func stripKey(_ key: KeyEvent) -> [Effect]? {
        guard state.runnersOpen || !frame.sidebarIDs.isEmpty, !state.runnerTree.rows.isEmpty, key.modifiers.isEmpty
        else {
            return nil
        }
        let rows = state.runnerTree.visible(collapsed: state.collapsedRunners)
        guard let id = state.stripSelection else {
            // Entering: at the end of the draft, where Down would go nowhere else.
            guard key.keyCode == Key.down.rawValue, state.editor.cursor == state.editor.text.count else { return nil }
            state.stripSelection = rows.first?.row.runner.id
            return []
        }
        guard let index = rows.firstIndex(where: { $0.row.runner.id == id }) else {
            state.stripSelection = nil
            return nil
        }
        switch key.keyCode {
            case Key.up.rawValue: state.stripSelection = rows[Swift.max(0, index - 1)].row.runner.id
            case Key.down.rawValue: state.stripSelection = rows[Swift.min(rows.count - 1, index + 1)].row.runner.id
            case Key.right.rawValue: state.collapsedRunners.remove(id)
            case Key.left.rawValue: collapseOrAscend(rows, at: index)
            case Key.enter.rawValue: return enterLane(rows[index].row.runner)
            case 0x1B: state.stripSelection = nil
            default:
                state.stripSelection = nil
                return nil
        }
        return []
    }

    /// Left: closes an open parent, otherwise goes to the parent.
    private mutating func collapseOrAscend(_ rows: [RunnerTree.Visible], at index: Int) {
        let item = rows[index]
        if item.hasChildren, item.hidden == 0 {
            state.collapsedRunners.insert(item.row.runner.id)
        } else if let parent = rows[..<index].last(where: { $0.row.depth < item.row.depth }) {
            state.stripSelection = parent.row.runner.id
        }
    }

    /// A click on the strip's row `index` as drawn: the same as selecting it and pressing Enter.
    mutating func clickStrip(row index: Int) -> [Effect] {
        guard state.pendingApproval == nil, frame.stripIDs.indices.contains(index),
            let runner = state.runners.first(where: { $0.id == frame.stripIDs[index] })
        else { return [] }
        return enterLane(runner)
    }

    /// A click on the sidebar's row `index`: the same as a click on the strip's row, Enter on that runner.
    mutating func clickSidebar(row index: Int) -> [Effect] {
        guard state.pendingApproval == nil, frame.sidebarIDs.indices.contains(index),
            let runner = state.runners.first(where: { $0.id == frame.sidebarIDs[index] })
        else { return [] }
        return enterLane(runner)
    }

    /// Ctrl+\\, and the keyboard's way to the sidebar when the mouse is off.
    func isToggleSidebar(_ key: KeyEvent) -> Bool {
        key.keyCode == 0x1C || (key.modifiers.contains(.ctrl) && key.keyCode == 0x5C)
    }

    /// Opens or closes the sidebar. A screen too narrow for it says so instead of seeming to ignore the command.
    mutating func toggleSidebar(announcing: Bool = false) -> [Effect] {
        state.sidebarOpen.toggle()
        if announcing, state.sidebarOpen, frame.columns > 0, frame.columns < Sidebar.minimumColumns {
            state.transcript.addNotice(
                "The sidebar needs \(Sidebar.minimumColumns) columns; this screen has \(frame.columns).", isError: false
            )
        }
        return []
    }

    /// Esc, once the selection and a picker have had it. One step back, never the draft or a turn: the strip's selection returns to the input, then a
    /// lane returns to main, then an open strip closes.
    mutating func escapePressed() -> [Effect] {
        if state.stripSelection != nil {
            state.stripSelection = nil
        } else if state.lane != nil {
            leaveLane()
        } else {
            state.runnersOpen = false
        }
        return []
    }
}
