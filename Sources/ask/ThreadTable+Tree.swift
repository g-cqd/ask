internal import AskTUI
internal import Synchronization

/// What the table answers about the tree of threads: names, how many work, how deep one is, what is under one.
extension ThreadTable {
    /// Names thread `name` `title` where it is shown; its id stays.
    func rename(_ name: String, to title: String) { state.withLock { $0.threads[name]?.title = title } }

    /// How many threads are at work: running, waiting on the person, or writing their summary.
    var working: Int { state.withLock { $0.threads.values.filter(\.state.isActive).count } }

    /// How deep thread `name` is: 1 for main's, one more for each thread above it.
    func depth(of name: String) -> Int {
        state.withLock { state in
            var depth = 0
            var next: String? = name
            while let current = next, let thread = state.threads[current], depth <= state.threads.count {
                depth += 1
                next = thread.parent
            }
            return depth
        }
    }

    /// `name` and every thread under it, `name` first, each before the threads under it.
    func subtree(_ name: String) -> [String] {
        state.withLock { state in
            var names: [String] = []
            var pending = [name]
            while let next = pending.popLast() {
                guard state.threads[next] != nil else { continue }
                names.append(next)
                pending += state.order.filter { state.threads[$0]?.parent == next }.reversed()
            }
            return names
        }
    }
}
