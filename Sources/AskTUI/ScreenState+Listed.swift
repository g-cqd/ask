/// Which runners a list shows (roadmap 0195, note n22): the list under the input leaves merged threads out, and what is under them;
/// `/threads` reaches them.
extension ScreenState {
    /// The tree's rows after collapsing, without merged threads and their rows when `hidingMerged`, and always without those merged
    /// longer than `threads.mergedShownFor`.
    func listedRows(hidingMerged: Bool) -> [RunnerTree.Visible] {
        let rows = runnerTree.visible(collapsed: collapsedRunners)
        guard hidingMerged || !expiredMerged.isEmpty else { return rows }
        var kept: [RunnerTree.Visible] = []
        var skippingBelow: Int?
        for item in rows {
            if let depth = skippingBelow, item.row.depth > depth { continue }
            skippingBelow = nil
            if item.row.runner.kind == .agent, item.row.runner.state == .merged,
                hidingMerged || expiredMerged.contains(item.row.runner.id)
            {
                skippingBelow = item.row.depth
                continue
            }
            kept.append(item)
        }
        return kept
    }

    /// Whether the list under the input is the tree: some thread it shows exists.
    var listsThreads: Bool { listedRows(hidingMerged: true).contains { $0.row.runner.kind == .agent } }
}
