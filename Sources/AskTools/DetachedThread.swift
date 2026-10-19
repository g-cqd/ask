internal import Darwin

/// A detached thread with a stack of the size asked for, made with `pthread_create` rather than Foundation's `Thread`.
///
/// The difference is memory, and it is on every interactive session, because the screen watches for a new build from
/// the start: the same watcher on a `Thread` raised idle memory by about 120 KiB (9,040 against 8,920 KiB, medians of
/// 15 runs, twice), and on this it raised it by none (ADR-0016, diary 24).
enum DetachedThread {
    /// Runs `work` on a new detached thread with `stackBytes` of stack.
    static func start(stackBytes: Int, _ work: @escaping @Sendable () -> Void) {
        var attributes = pthread_attr_t()
        pthread_attr_init(&attributes)
        pthread_attr_setstacksize(&attributes, stackBytes)
        pthread_attr_setdetachstate(&attributes, PTHREAD_CREATE_DETACHED)
        defer { pthread_attr_destroy(&attributes) }
        let box = Unmanaged.passRetained(Box(work))
        var thread = pthread_t(bitPattern: 0)
        let status = unsafe pthread_create(
            &thread, &attributes,
            { raw in
                let box = unsafe Unmanaged<Box>.fromOpaque(raw).takeRetainedValue()
                box.work()
                return nil
            }, box.toOpaque())
        if status != 0 { box.release() }
    }

    /// Carries the closure through the C thread entry point.
    private final class Box: Sendable {
        let work: @Sendable () -> Void
        init(_ work: @escaping @Sendable () -> Void) { self.work = work }
    }
}
