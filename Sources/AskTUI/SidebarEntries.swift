internal import TerminalKitStyle
internal import TerminalKitText

/// The sidebar's rows before they are windowed (roadmap 0194): a Threads section, the main conversation then its threads as a tree
/// (with the jobs a thread started under it), and a Jobs section. A section with nothing in it is left out; while a lane is shown, Threads always is, for its way back to main.
struct SidebarEntries {
    struct Entry: Equatable {
        var text: String
        var style: Style
        /// The runner, ``RunnerStrip/mainID`` for the conversation, "" for a heading or a gap.
        var id = ""
    }

    private(set) var entries: [Entry] = []

    init(_ state: ScreenState, columns: Int) {
        let rows = state.runnerTree.visible(collapsed: state.collapsedRunners)
        // A runner belongs to its root's section: a job a thread started stays in the thread's tree.
        var rootKind = RunnerInfo.Kind.job
        var threads: [RunnerTree.Visible] = []
        var jobs: [RunnerTree.Visible] = []
        for item in rows {
            if item.row.depth == 0 { rootKind = item.row.runner.kind }
            if rootKind == .agent { threads.append(item) } else { jobs.append(item) }
        }
        if !threads.isEmpty || state.lane != nil {
            entries.append(
                Self.heading("Threads", threads.map(\.row.runner).filter { $0.kind == .agent }, columns: columns)
            )
            let shown = state.lane?.id
            entries.append(
                Entry(
                    text: ScreenComposer.ellipsized("◆ main", cells: columns).shown,
                    style: Self.style(
                        active: true,
                        shown: shown == nil,
                        chosen: state.stripSelection == RunnerStrip.mainID
                    ),
                    id: RunnerStrip.mainID
                )
            )
            let lasts = Self.lastSiblings(threads.map(\.row.depth))
            var open: [Bool] = []  // Whether each ancestor depth has siblings still to come: its line continues.
            for (index, item) in threads.enumerated() {
                let depth = item.row.depth
                open = Array(open.prefix(depth))
                let guide = open.map { $0 ? "│ " : "  " }.joined() + (lasts[index] ? "└ " : "├ ")
                open.append(!lasts[index])
                entries.append(row(item, prefix: guide, state: state, columns: columns))
            }
        }
        if !jobs.isEmpty {
            if !entries.isEmpty { entries.append(Entry(text: "", style: .default)) }
            entries.append(Self.heading("Jobs", jobs.map(\.row.runner), columns: columns))
            for item in jobs {
                let indent = String(repeating: "  ", count: Swift.min(item.row.depth, columns / 4))
                entries.append(row(item, prefix: indent, state: state, columns: columns))
            }
        }
    }

    /// A section's name, and how many of its runners are active.
    private static func heading(_ name: String, _ runners: [RunnerInfo], columns: Int) -> Entry {
        let active = runners.filter(\.state.isActive).count
        let text = active > 0 ? "\(name) · \(active) running" : name
        return Entry(text: ScreenComposer.ellipsized(text, cells: columns).shown, style: Style(bold: true, dim: true))
    }

    /// Whether each row, given in preorder by depth, is the last child of its parent.
    private static func lastSiblings(_ depths: [Int]) -> [Bool] {
        depths.indices.map { index in
            let depth = depths[index]
            let next = depths[(index + 1)...].first { $0 <= depth }
            return next == nil || next! < depth
        }
    }

    /// One runner: the guide, its state mark, its name and what it is doing, and how long it has run while it is active.
    private func row(_ item: RunnerTree.Visible, prefix: String, state: ScreenState, columns: Int) -> Entry {
        let runner = item.row.runner
        let progress = state.runnerProgress[runner.id]
        let name = runner.kind == .job ? String(runner.name.filter { $0 != "[" && $0 != "]" }) : runner.name
        var text =
            prefix + Self.mark(runner.state, spinner: progress?.indicator) + " " + name + " "
            + runner.detail.replacing("\n", with: " ")
        if item.hidden > 0 { text = prefix + "+\(item.hidden) " + String(text.dropFirst(prefix.count)) }
        let duration = runner.state.isActive ? progress?.duration(localized: state.blocks.localizedDurations) : nil
        return Entry(
            text: Self.fitted(text, trailing: duration, columns: columns),
            style: Self.style(
                active: runner.state.isActive,
                shown: state.lane?.id == runner.id,
                chosen: state.stripSelection == runner.id
            ),
            id: runner.id
        )
    }

    /// The state at a glance: a running runner's spinner, `?` waiting on the person, then `✓`, `✗` or `■`.
    private static func mark(_ state: RunnerInfo.State, spinner: String?) -> String {
        switch state {
            case .running: spinner ?? "●"
            case .waitingForApproval: "?"
            case .done: "✓"
            case .failed: "✗"
            case .stopped: "■"
        }
    }

    /// Active runners at full brightness and ended ones dim; the one whose lane is shown bold; the keyboard's, inverse.
    private static func style(active: Bool, shown: Bool, chosen: Bool) -> Style {
        Style(bold: shown, dim: !active && !shown && !chosen, inverse: chosen)
    }

    /// `text` cut with `…` to leave room for `trailing` at the right edge, when there is one and room for it.
    private static func fitted(_ text: String, trailing: String?, columns: Int) -> String {
        guard let trailing, UnicodeWidth.displayWidth(of: trailing) + 6 <= columns else {
            let cut = ScreenComposer.ellipsized(text, cells: columns)
            return cut.shown + cut.mark
        }
        let room = columns - UnicodeWidth.displayWidth(of: trailing) - 1
        let cut = ScreenComposer.ellipsized(text, cells: room)
        return cut.shown + cut.mark
            + String(repeating: " ", count: Swift.max(1, columns - cut.cells - UnicodeWidth.displayWidth(of: trailing)))
            + trailing
    }
}
