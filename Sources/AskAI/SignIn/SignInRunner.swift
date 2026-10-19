/// Runs a ``BrowserSignIn``: shows the link, polls until the user finishes, and returns what the sign-in ends in.
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
    ///   - show: called once with what the user is shown: the link and what to do there.
    /// - Returns: what the sign-in ends in.
    /// - Throws: ``SignInError``; ``SignInError/cancelled`` when the task is cancelled, before any further request.
    public func run<Flow: BrowserSignIn>(_ flow: Flow, show: @Sendable (SignInPrompt) -> Void) async throws(SignInError)
        -> Flow.Outcome
    {
        let started = try await flow.start()
        show(SignInPrompt(url: started.url, instructions: started.instructions))
        let deadline = clock.now.advanced(by: started.window)
        var interval = started.interval
        var waits = !flow.pollsImmediately
        while true {
            try live(until: deadline)
            if waits {
                try await wait(min(interval, clock.now.duration(to: deadline)))
                try live(until: deadline)
            }
            let polled = try await flow.poll(started.session)
            try live(until: deadline)
            switch polled {
                case .pending: waits = true
                case .slowDown:
                    interval += .seconds(5)
                    waits = true
                case .complete(let grant): return try await flow.finish(started.session, grant: grant)
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
