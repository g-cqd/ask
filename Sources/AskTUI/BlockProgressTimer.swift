/// No idle work: animation exists only while a tool or thinking block is live.
struct BlockProgressTimer {
    private var task: Task<Void, Never>?

    mutating func update(wanted: Bool, post: @escaping @Sendable () -> Void) {
        guard wanted else {
            stop()
            return
        }
        guard task == nil else { return }
        task = Task {
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
                if !Task.isCancelled { post() }
            }
        }
    }

    mutating func stop() {
        task?.cancel()
        task = nil
    }
}
