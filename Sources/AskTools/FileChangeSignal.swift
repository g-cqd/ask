internal import AemiIO

/// The files of a set that changed, one report per burst, through AemiIO's `KqueueWatcher` (aemi ADR 0016): saved in
/// place or atomically, removed, or created later, directories included. A save or a link raises several events; the
/// report waits until they have been quiet for a moment, so a consumer looks once, after the write.
///
/// One watcher, so one thread, serves every file a screen watches (the configuration and ask's own executable): a second
/// watcher measured 0.2 MiB more at idle.
public enum FileChangeSignal {
    /// The watched paths that changed in each burst, as given, until the consumer is cancelled, which stops the watcher.
    /// - Parameters:
    ///   - paths: the files to watch, existing or not.
    ///   - quiet: how long the files must stay unchanged before a report.
    /// - Returns: the reports; a stream that ends at once when the system refuses a watcher.
    public static func changes(of paths: [String], quiet: Duration = .milliseconds(150)) -> AsyncStream<Set<String>> {
        AsyncStream { continuation in
            guard let watcher = try? KqueueWatcher() else {
                continuation.finish()
                return
            }
            for path in paths { watcher.watchFile(path) }
            let task = Task {
                let burst = Burst(quiet: quiet) { continuation.yield($0) }
                for await event in watcher.events {
                    if case .fileChanged(let path) = event { await burst.add(path) }
                }
                await burst.cancel()
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
                watcher.stop()
            }
        }
    }

    /// The paths changed since the last report, and the quiet period that ends with the next one.
    private actor Burst {
        private let quiet: Duration
        private let report: @Sendable (Set<String>) -> Void
        private var paths: Set<String> = []
        private var pending: Task<Void, Never>?

        init(quiet: Duration, report: @escaping @Sendable (Set<String>) -> Void) {
            self.quiet = quiet
            self.report = report
        }

        func add(_ path: String) {
            paths.insert(path)
            pending?.cancel()
            pending = Task {
                try? await Task.sleep(for: quiet)
                if !Task.isCancelled { flush() }
            }
        }

        func cancel() { pending?.cancel() }

        private func flush() {
            guard !paths.isEmpty else { return }
            report(paths)
            paths = []
        }
    }
}
