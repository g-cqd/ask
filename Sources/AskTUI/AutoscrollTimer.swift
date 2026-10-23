/// Posts `.tick` while the controller wants edge autoscroll, and nothing otherwise. A stale timer is cancelled, never left to tick a
/// finished drag.
struct AutoscrollTimer {
    private var task: Task<Void, Never>?

    mutating func update(wanted: Bool, post: @escaping @Sendable () -> Void) {
        if wanted {
            guard task == nil else { return }
            task = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: DragAutoscroll.interval)
                    if !Task.isCancelled { post() }
                }
            }
        } else {
            stop()
        }
    }

    mutating func stop() {
        task?.cancel()
        task = nil
    }
}
