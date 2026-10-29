/// The one-shot timers of a window that closes by itself: the quit window and the sandbox note.
enum ScreenTimer {
    /// Sends `event` to `sink` once `delay` has passed.
    static func after(_ delay: Duration, send event: ScreenEvent, to sink: AsyncStream<ScreenEvent>.Continuation) {
        Task {
            try? await Task.sleep(for: delay)
            sink.yield(event)
        }
    }
}
