public import Foundation

/// Runs a ``BrowserSignIn``: shows the link, polls until the user finishes, and returns the key.
///
/// The clock is injected so a test passes ten minutes in no time. Time is measured on it, not summed from waits, so a
/// server that answers slowly cannot stretch the deadline.
public struct SignInRunner<C: Clock<Duration>>: Sendable {
    private let clock: C

    /// A runner that waits on `clock`.
    public init(clock: C) { self.clock = clock }

    /// Signs in.
    /// - Parameters:
    ///   - flow: the provider's sign-in.
    ///   - show: called once with the link for the user to open.
    /// - Returns: the key the sign-in issued.
    /// - Throws: ``SignInError``; ``SignInError/cancelled`` when the task is cancelled, before any further request.
    public func run<Flow: BrowserSignIn>(_ flow: Flow, show: @Sendable (URL) -> Void) async throws(SignInError)
        -> StoredKey
    {
        let started = try await flow.start()
        show(started.url)
        let deadline = clock.now.advanced(by: started.window)
        var waits = !flow.pollsImmediately
        while true {
            try live(until: deadline)
            if waits {
                try await wait(min(flow.pollInterval, clock.now.duration(to: deadline)))
                try live(until: deadline)
            }
            let polled = try await flow.poll(started.session)
            try live(until: deadline)
            switch polled {
                case .pending: waits = true
                case .complete(let token):
                    let key = try await flow.finish(started.session, token: token)
                    return StoredKey(key: key, obtainedAt: flow.timestamp())
            }
        }
    }

    private func live(until deadline: C.Instant) throws(SignInError) {
        if Task.isCancelled { throw .cancelled }
        if clock.now >= deadline { throw .timedOut }
    }

    private func wait(_ duration: Duration) async throws(SignInError) {
        do { try await clock.sleep(for: duration) } catch { throw .cancelled }
    }
}
