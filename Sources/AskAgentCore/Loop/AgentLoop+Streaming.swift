internal import AskAI

extension AgentLoop {
    /// What to do about a request that failed before its response was complete.
    private enum FailureOutcome {
        /// Too long for the window: `run` compacts the conversation and sends a shorter one.
        case overflow(String)
        /// Transient, and nothing of it reached the screen: wait, then send it again.
        case retry(after: Duration, reason: String)
        /// End the request with this error.
        case fail(AgentError)
    }

    /// Streams `request` and assembles the response, retrying transient failures.
    func stream(_ request: ModelRequest, events: (AgentEvent) -> Void) async throws(AgentError)
        -> AssembledResponse
    {
        var attempt = 1
        while true {
            var assembler = ResponseAssembler()
            var shown = false
            do {
                for try await event in provider.stream(request) {
                    try assembler.apply(event)
                    shown = true
                    events(.model(event))
                }
            } catch let error as ResponseAssemblyError {
                throw .assembly(error)
            } catch {
                switch outcome(of: error, shown: shown, attempt: attempt) {
                    case .overflow(let reason): throw .contextOverflow(reason)
                    case .fail(let error): throw error
                    case .retry(let delay, let reason):
                        events(.retrying(attempt: attempt + 1, of: retry.maximumAttempts, delay: delay, reason: reason))
                        do { try await clock.sleep(for: delay) } catch { throw .cancelled }
                        attempt += 1
                        continue
                }
            }
            guard !Task.isCancelled else { throw .cancelled }
            do { return try assembler.finish() } catch { throw .assembly(error) }
        }
    }

    /// Decides what a failed attempt means. A refusal for length is never retried as it was, and teaches the loop
    /// the window when it names one. A transient failure is retried only when nothing of the attempt reached the
    /// screen, since a second attempt would otherwise repeat what was already shown.
    private func outcome(of error: any Error, shown: Bool, attempt: Int) -> FailureOutcome {
        if Task.isCancelled { return .fail(.cancelled) }
        let advice = error as? any RetryAdvice
        if let advice, advice.isContextOverflow {
            if let window = advice.reportedContextWindow { learnedWindow.learn(window) }
            return .overflow(String(describing: error))
        }
        guard !shown, attempt < retry.maximumAttempts, let advice, advice.isRetryable else {
            return .fail(.provider(String(describing: error)))
        }
        return .retry(
            after: retry.delay(after: attempt, requested: advice.retryAfter), reason: String(describing: error))
    }
}
