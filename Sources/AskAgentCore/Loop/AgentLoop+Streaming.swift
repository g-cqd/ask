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
    func stream(_ request: ModelRequest, events: (AgentEvent) -> Void) async throws(AgentError) -> AssembledResponse {
        // Without handing over, a retry is never cut short, so there is always a response or an error.
        guard let response = try await stream(request, events: events, handsOver: false) else { throw .cancelled }
        return response
    }

    /// Streams `request` and assembles the response, retrying transient failures.
    /// - Parameters:
    ///   - request: what is sent.
    ///   - events: each event of the response, as it arrives.
    ///   - handsOver: whether a change offered while a retry waits ends the wait, so the request goes to the new loop.
    /// - Returns: the response, or nil when a change was offered while a retry waited: the caller sends the request again with it.
    /// - Throws: an ``AgentError`` when the request fails for good, is too long for the window, or the turn is stopped.
    func stream(_ request: ModelRequest, events: (AgentEvent) -> Void, handsOver: Bool) async throws(AgentError)
        -> AssembledResponse?
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
            switch try await recover(decided, attempt: &attempt, events: events, handsOver: handsOver) {
                case .carryOn(let partial): return partial
                case .handOver: return nil
                case .again: continue
            }
        }
    }

    /// What follows a failure the loop recovers from.
    private enum Recovery {
        /// Keep what arrived and ask the model to carry on.
        case carryOn(AssembledResponse)
        /// Send the request again.
        case again
        /// A change was offered while waiting: the turn takes it and sends the request with it.
        case handOver
    }

    /// Acts on what a failure means: throws for the end of the request, or waits and says how to go on.
    private func recover(
        _ decided: FailureOutcome, attempt: inout Int, events: (AgentEvent) -> Void, handsOver: Bool
    ) async throws(AgentError) -> Recovery {
        switch decided {
            case .overflow(let reason): throw .contextOverflow(reason)
            case .fail(let error): throw error
            case .carryOn(let delay, let reason, var partial):
                if try await !waitedForNetwork(reason: reason, events: events) {
                    events(.retrying(attempt: attempt + 1, of: retry.maximumAttempts, delay: delay, reason: reason))
                    do { try await clock.sleep(for: delay) } catch { throw .cancelled }
                }
                partial.stopReason = Self.droppedStopReason
                return .carryOn(partial)
            case .retry(let delay, let reason):
                // Offline, the wait is for the network, and costs no attempt: it is not the request that failed.
                if try await waitedForNetwork(reason: reason, events: events) { return .again }
                events(.retrying(attempt: attempt + 1, of: retry.maximumAttempts, delay: delay, reason: reason))
                if try await pause(for: delay, handsOver: handsOver) { return .handOver }
                attempt += 1
                return .again
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
