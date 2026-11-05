internal import TerminalKitStyle
internal import TerminalKitText

/// The sidebar's rows before they are windowed (roadmap 0194): the main conversation, always first so the panel never jumps, with its
/// threads as a tree under it (and the jobs a thread started under that thread), then a Jobs section when there are jobs; and the
/// line of counts the panel ends with (note n24).
struct SidebarEntries {
    struct Entry: Equatable {
        var text: String
        var style: Style
        /// The runner, ``RunnerStrip/mainID`` for the conversation, "" for a heading or a gap.
        var id = ""
    }

    private(set) var entries: [Entry] = []
    /// The panel's last row: what is running and what waits.
    private(set) var counts = Entry(text: "", style: .default)

    /// - Parameters:
    ///   - state: what the screen holds.
    ///   - columns: the width each row is cut to.
    ///   - gap: whether an empty row comes before the Jobs section; the list under the input has no rows to spare.
    ///   - hidingMerged: whether merged threads are left out, as the list under the input leaves them (note n22).
    init(_ state: ScreenState, columns: Int, gap: Bool = true, hidingMerged: Bool = false) {
        let rows = state.listedRows(hidingMerged: hidingMerged)
        // A runner belongs to its root's section: a job a thread started stays in the thread's tree.
        var rootKind = RunnerInfo.Kind.job
        var threads: [RunnerTree.Visible] = []
        var jobs: [RunnerTree.Visible] = []
        for item in rows {
            if item.row.depth == 0 { rootKind = item.row.runner.kind }
            if rootKind == .agent { threads.append(item) } else { jobs.append(item) }
        }
        counts = Self.counts(state.runnerTree.runners, columns: columns)
        let shown = state.lane?.id
        entries.append(
            Entry(
                // In a lane it says what it is: the way back.
                text:
                    ScreenComposer.ellipsized(
                        state.lane == nil ? "◆ main" : "◆ main  back to the conversation",
                        cells: columns
                    )
                    .shown,
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
        if !jobs.isEmpty {
            if gap { entries.append(Entry(text: "", style: .default)) }
            entries.append(Entry(text: "Jobs", style: Style(bold: true, dim: true)))
            for item in jobs {
                let indent = String(repeating: "  ", count: Swift.min(item.row.depth, columns / 4))
                entries.append(row(item, prefix: indent, state: state, columns: columns))
            }
        }
    }

    /// What is running, for the panel's last row: active threads, running jobs, and what waits on the person; blank when nothing is.
    private static func counts(_ runners: [RunnerInfo], columns: Int) -> Entry {
        func count(_ number: Int, _ noun: String) -> String? {
            number > 0 ? "\(number) \(noun)\(number == 1 ? "" : "s")" : nil
        }
        let threads = runners.filter { $0.kind == .agent && $0.state == .running }.count
        let jobs = runners.filter { $0.kind == .job && $0.state == .running }.count
        let waiting = runners.filter { $0.state == .waitingForApproval }.count
        let running = [count(threads, "thread"), count(jobs, "job")].compactMap { $0 }.joined(separator: ", ")
        let waits = waiting > 0 ? "\(waiting) waiting" : nil
        let full = [running.isEmpty ? nil : running + " running", waits].compactMap { $0 }.joined(separator: " · ")
        // Narrower, the kinds are summed: the count still fits.
        let short = [threads + jobs > 0 ? "\(threads + jobs) running" : nil, waits].compactMap { $0 }
            .joined(separator: " · ")
        // Nothing running says nothing (note n38): the row stays, blank, so the tree does not move when something starts.
        let text = full.isEmpty ? "" : UnicodeWidth.displayWidth(of: full) <= columns ? full : short
        let cut = ScreenComposer.ellipsized(text, cells: columns)
        return Entry(text: cut.shown + cut.mark, style: Style(dim: true))
    }

    /// Whether each row, given in preorder by depth, is the last child of its parent.
    private static func lastSiblings(_ depths: [Int]) -> [Bool] {
        depths.indices.map { index in
            let depth = depths[index]
            let next = depths[(index + 1)...].first { $0 <= depth }
            return next.map { $0 < depth } ?? true
        }
    }

    /// One runner: the guide, its state mark, its name and what it is doing, and how long it has run while it is active.
    private func row(_ item: RunnerTree.Visible, prefix: String, state: ScreenState, columns: Int) -> Entry {
        let runner = item.row.runner
        let progress = state.runnerProgress[runner.id]
        let name = runner.kind == .job ? String(runner.name.filter { $0 != "[" && $0 != "]" }) : runner.name
        var text =
            prefix
            + Self.mark(
                runner.state,
                kind: runner.kind,
                spinner: progress?.indicator,
                quietKind: Self.quiet(runner, progress, state) ? runner.kind : nil
            )
            + " " + name + " "
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

    /// How long a running runner may do nothing before its row shows its kind rather than a spinner.
    static let quietAfter: Duration = .seconds(3)

    /// Whether `runner` has done nothing for ``quietAfter``: no event, no output, since it last did or since it started.
    private static func quiet(_ runner: RunnerInfo, _ progress: BlockProgress?, _ state: ScreenState) -> Bool {
        guard runner.state == .running, let progress else { return false }
        let last = state.runnerActivity[runner.id].map { Swift.max($0, progress.started) } ?? progress.started
        return progress.sampled - last >= quietAfter
    }

    /// The state at a glance: a running runner's spinner while it works and its kind once quiet (`◇` a thread, `$` a job), `?` waiting
    /// on the person, then `✓`, `✗` or `■`.
    private static func mark(
        _ state: RunnerInfo.State,
        kind: RunnerInfo.Kind,
        spinner: String?,
        quietKind: RunnerInfo.Kind?
    ) -> String {
        switch state {
            case .running:
                switch quietKind {
                    case .agent: "◇"
                    case .job: "$"
                    case nil: spinner ?? "●"
                }
            case .waitingForApproval: "?"
            case .merging: spinner ?? "●"
            case .held: "◌"
            // A thread that finished and is not merged is idle (`threads.merge` ask declined): it can go on, or merge.
            case .done where kind == .agent: "○"
            case .done, .merged: "✓"
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
