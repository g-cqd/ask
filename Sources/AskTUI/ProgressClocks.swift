/// The transcript's progress clocks by block, with the blocks whose clock has not ended kept beside them (note n55): every event asks
/// whether anything is live and which tool runs last, and a long session holds thousands of ended clocks, so those answers come from
/// the few live blocks, not a scan of all.
///
/// The clocks that run and those that have ended are in two stores. The render thread holds the last frame's state, so a clock
/// that changes copies the store it is in, and the copy it replaces is freed clock by clock: with one store, every animation
/// tick copied and freed the clock of every block the session had ever shown (1.4 ms a tick at 35,000 blocks; diary
/// 2026-11-15-12). A tick now copies the clocks that run, which are few.
struct ProgressClocks: Equatable, Sendable {
    /// The clocks that have not ended: what a tick changes.
    private(set) var running: [Int: BlockProgress] = [:]
    /// The clocks that have ended: changed only when one ends, is replaced or is removed.
    private(set) var ended: [Int: BlockProgress] = [:]
    /// The blocks whose clock has not ended.
    private(set) var live: Set<Int> = []

    subscript(index: Int) -> BlockProgress? {
        get { running[index] ?? ended[index] }
        set {
            guard let newValue else {
                if running.removeValue(forKey: index) != nil { live.remove(index) } else { ended[index] = nil }
                return
            }
            if newValue.ended == nil {
                // Looked up before it is removed: a removal that finds nothing would still copy a store the last frame shares.
                if running.updateValue(newValue, forKey: index) == nil {
                    live.insert(index)
                    if ended[index] != nil { ended[index] = nil }
                }
            } else {
                ended[index] = newValue
                if running.removeValue(forKey: index) != nil { live.remove(index) }
            }
        }
    }

    /// Every clock, in no order.
    var values: [BlockProgress] { Array(running.values) + Array(ended.values) }
    var isEmpty: Bool { running.isEmpty && ended.isEmpty }

    mutating func removeAll(keepingCapacity keep: Bool = false) {
        running.removeAll(keepingCapacity: keep)
        ended.removeAll(keepingCapacity: keep)
        live.removeAll(keepingCapacity: keep)
    }
}
