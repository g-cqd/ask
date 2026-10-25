/// One runner snapshot and its preorder rows, built when the runners change, never on a keystroke frame.
///
/// First occurrence of an id wins; siblings retain update order. Missing parents become roots. Cycles are broken at the first unseen node in update
/// order, and each id is shown once, so damaged input cannot hide a job or loop. Construction is O(n) time and space (expected hash-table costs),
/// n = supplied runners. Traversal is iterative: a deep chain never consumes the call stack.
public struct RunnerTree: Sendable, Equatable {
    public struct Row: Sendable, Equatable {
        public let runner: RunnerInfo
        public let depth: Int
    }

    /// Unique nodes in supplied order.
    public let runners: [RunnerInfo]
    /// Roots and their descendants, for the strip and later the sidebar.
    public let rows: [Row]
    /// What the status counts, independent of how much of the strip fits.
    public let activeCount: Int
    public let activeJobCount: Int

    public init(_ supplied: [RunnerInfo] = []) {
        var ids = Set<String>()
        let runners = supplied.filter { ids.insert($0.id).inserted }
        self.runners = runners
        activeCount = runners.filter { $0.state.isActive }.count
        activeJobCount = runners.filter { $0.kind == .job && $0.state.isActive }.count
        rows = Self.flatten(runners, ids: ids)
    }

    private static func flatten(_ runners: [RunnerInfo], ids: Set<String>) -> [Row] {
        var children: [String: [Int]] = [:]
        var roots: [Int] = []
        for (index, runner) in runners.enumerated() {
            if let parent = runner.parentID, parent != runner.id, ids.contains(parent) {
                children[parent, default: []].append(index)
            } else {
                roots.append(index)
            }
        }
        var visited = Set<String>()
        var rows: [Row] = []
        // After normal roots, seed every node as a fallback root. Already-visited seeds are skipped; cyclic components are still shown.
        for root in roots + Array(runners.indices) {
            var pending = [(root, 0)]
            while let (index, depth) = pending.popLast() {
                let runner = runners[index]
                guard visited.insert(runner.id).inserted else { continue }
                rows.append(Row(runner: runner, depth: depth))
                for child in (children[runner.id] ?? []).reversed() { pending.append((child, depth + 1)) }
            }
        }
        return rows
    }
}
