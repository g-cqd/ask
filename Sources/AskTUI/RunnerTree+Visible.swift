extension RunnerTree {
    /// A row the strip may draw: collapsed parents hide their descendants and say how many.
    struct Visible: Equatable {
        let row: Row
        let hidden: Int
        let hasChildren: Bool
    }

    /// The rows left after collapsing, in preorder.
    /// - Parameter collapsed: ids whose descendants are hidden. An id with no children collapses nothing.
    /// - Returns: the rows to draw, each with how many it hides.
    /// - Complexity: O(n), n = rows: each hidden row is skipped once.
    func visible(collapsed: Set<String>) -> [Visible] {
        var shown: [Visible] = []
        var index = 0
        while index < rows.count {
            let row = rows[index]
            let hasChildren = index + 1 < rows.count && rows[index + 1].depth > row.depth
            guard hasChildren, collapsed.contains(row.runner.id) else {
                shown.append(Visible(row: row, hidden: 0, hasChildren: hasChildren))
                index += 1
                continue
            }
            var end = index + 1
            while end < rows.count, rows[end].depth > row.depth { end += 1 }
            shown.append(Visible(row: row, hidden: end - index - 1, hasChildren: true))
            index = end
        }
        return shown
    }
}
