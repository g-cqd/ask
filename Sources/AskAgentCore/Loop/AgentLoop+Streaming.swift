internal import AskAI

extension AgentLoop {
    /// What to do about a request that failed before its response was complete.
    private enum FailureOutcome {
        /// Too long for the window: `run` compacts the conversation and sends a shorter one.
        case overflow(String)
        /// Transient, and nothing of it reached the screen: wait, then send it again.
        case retry(after: Duration, reason: String)
        /// Transient, after text was shown (roadmap 0141): wait, then keep what arrived and ask the model to carry on.
        case carryOn(after: Duration, reason: String, partial: AssembledResponse)
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
            let failure: any Error
            do {
                for try await event in provider.stream(request) {
                    try assembler.apply(event)
                    shown = true
                    events(.model(event))
                }
                guard !Task.isCancelled else { throw AgentError.cancelled }
                let response = try assembler.finish()
                drops.reset()
                return response
            } catch let error as AgentError {
                throw error
            } catch ResponseAssemblyError.incomplete {
                // The stream ended before the response did: a connection closed between two events.
                failure = ClosedEarly()
            } catch let error as ResponseAssemblyError {
                throw .assembly(error)
            } catch {
                failure = error
            }
            let decided = outcome(of: failure, shown: shown, attempt: attempt, partial: assembler.partial())
            if let partial = try await recover(decided, attempt: &attempt, events: events) { return partial }
        }
    }

    /// Acts on what a failure means: throws for the end of the request, waits and returns the part that arrived to carry on from, or
    /// waits and returns nil to send the request again.
    private func recover(_ decided: FailureOutcome, attempt: inout Int, events: (AgentEvent) -> Void)
        async throws(AgentError) -> AssembledResponse?
    {
        switch decided {
            case .overflow(let reason): throw .contextOverflow(reason)
            case .fail(let error): throw error
            case .carryOn(let delay, let reason, var partial):
                if try await !waitedForNetwork(reason: reason, events: events) {
                    events(.retrying(attempt: attempt + 1, of: retry.maximumAttempts, delay: delay, reason: reason))
                    do { try await clock.sleep(for: delay) } catch { throw .cancelled }
                }
                partial.stopReason = Self.droppedStopReason
                return partial
            case .retry(let delay, let reason):
                // Offline, the wait is for the network, and costs no attempt: it is not the request that failed.
                if try await waitedForNetwork(reason: reason, events: events) { return nil }
                events(.retrying(attempt: attempt + 1, of: retry.maximumAttempts, delay: delay, reason: reason))
                do { try await clock.sleep(for: delay) } catch { throw .cancelled }
                attempt += 1
                return nil
        }
    }

    /// With the network gone, waits for it to come back, up to ``networkWait``.
    /// - Returns: whether it waited, and the network is back; false when the network was there all along.
    /// - Throws: ``AgentError/cancelled`` when the turn is stopped while waiting, or the failure when the network does not come back.
    private func waitedForNetwork(reason: String, events: (AgentEvent) -> Void) async throws(AgentError) -> Bool {
        guard let network, await !network.isSatisfied() else { return false }
        events(.waitingForNetwork)
        let back = await network.waitUntilSatisfied(atMost: networkWait)
        guard !Task.isCancelled else { throw .cancelled }
        guard back else { throw .provider(reason) }
        return true
    }

    /// Decides what a failed attempt means. A refusal for length is never retried as it was, and teaches the loop
    /// the window when it names one. A transient failure is retried as it was when no text of the attempt reached the
    /// screen, and carried on from what arrived when some did.
    private func outcome(of error: any Error, shown: Bool, attempt: Int, partial: AssembledResponse?) -> FailureOutcome
    {
        if Task.isCancelled { return .fail(.cancelled) }
        let advice = error as? any RetryAdvice
        if let advice, advice.isContextOverflow {
            if let window = advice.reportedContextWindow { learnedWindow.learn(window) }
            return .overflow(String(describing: error))
        }
        let reason = String(describing: error)
        let failed = FailureOutcome.fail(.provider(reason))
        guard let advice, advice.isRetryable else { return failed }
        // Text was shown: a second attempt would repeat it, so what arrived is kept and the model carries on (roadmap 0141). Only
        // reasoning shown is sent again whole, as if nothing had been.
        if shown, let partial {
            let drops = drops.dropped()
            guard drops < retry.maximumAttempts else { return failed }
            return .carryOn(
                after: retry.delay(after: drops, requested: advice.retryAfter), reason: reason, partial: partial)
        }
        guard attempt < retry.maximumAttempts else { return failed }
        return .retry(after: retry.delay(after: attempt, requested: advice.retryAfter), reason: reason)
    }
}
