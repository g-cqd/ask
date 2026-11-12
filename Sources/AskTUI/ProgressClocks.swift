/// The transcript's progress clocks by block, with the blocks whose clock has not ended kept beside them (note n55): every event asks
/// whether anything is live and which tool runs last, and a long session holds thousands of ended clocks, so those answers come from
/// the few live blocks, not a scan of all.
struct ProgressClocks: Equatable, Sendable {
    private var clocks: [Int: BlockProgress] = [:]
    /// The blocks whose clock has not ended.
    private(set) var live: Set<Int> = []

    subscript(index: Int) -> BlockProgress? {
        get { clocks[index] }
        set {
            clocks[index] = newValue
            if let newValue, newValue.ended == nil { live.insert(index) } else { live.remove(index) }
        }
    }

    var keys: Dictionary<Int, BlockProgress>.Keys { clocks.keys }
    var values: Dictionary<Int, BlockProgress>.Values { clocks.values }
    var isEmpty: Bool { clocks.isEmpty }

    mutating func removeAll(keepingCapacity keep: Bool = false) {
        clocks.removeAll(keepingCapacity: keep)
        live.removeAll(keepingCapacity: keep)
    }
}
