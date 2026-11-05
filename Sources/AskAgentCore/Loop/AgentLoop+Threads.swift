/// The thread hook points (roadmap 0195, for 0192), asked by the conversation that runs threads on this loop. Hooks are asked in order,
/// each within its deadline, as at every other point: rewrites chain, the first block ends the chain, and a hook that misses its deadline
/// is passed over (a `thread.start` hook that fails closed refuses the thread).
extension AgentLoop {
    /// Where a thread point's timeouts go: they have no run's events to join.
    private static let unheard: @Sendable (AgentEvent) -> Void = { _ in }

    /// What becomes of a thread about to start.
    public enum ThreadStartOutcome: Sendable, Equatable {
        /// Start it, on this task.
        case start(String)
        /// Do not; this says why.
        case refused(String)
    }

    /// `start` through the hooks, in order.
    public func startingThread(_ start: ThreadStart) async -> ThreadStartOutcome {
        var prompt = start.prompt
        for hook in hooks {
            let asked = ThreadStart(name: start.name, parent: start.parent, prompt: prompt)
            let fallback: ThreadStartDecision = hook.failureMode == .closed ? .block("timed out") : .allow
            // @dl:accept -- each hook point asks its hooks the same way through HookDeadline.ask; the point, answer type and fallback are the data
            let decision = await HookDeadline.ask(
                hook,
                at: "thread.start",
                clock: clock,
                orElse: fallback,
                timedOut: Self.unheard
            ) {
                await hook.threadStart(asked)
            }
            switch decision {
                case .allow: continue
                case .block(let reason): return .refused("The hook \(hook.name) refused this thread: \(reason)")
                case .rewrite(let rewritten) where !rewritten.allSatisfy(\.isWhitespace): prompt = rewritten
                case .rewrite: continue
            }
        }
        return .start(prompt)
    }

    /// The hooks' instructions for `merge`'s summary, in order; blank ones are left out.
    public func mergeInstructions(_ merge: ThreadMerge) async -> [String] {
        var instructions: [String] = []
        for hook in hooks {
            // @dl:accept -- each hook point asks its hooks the same way through HookDeadline.ask; the point, answer type and fallback are the data
            let decision = await HookDeadline.ask(
                hook,
                at: "thread.merge",
                clock: clock,
                orElse: .allow,
                timedOut: Self.unheard
            ) {
                await hook.threadMerge(merge)
            }
            if case .instructions(let text) = decision, !text.allSatisfy(\.isWhitespace) { instructions.append(text) }
        }
        return instructions
    }

    /// `summary` through the hooks, in order, each seeing the one before's.
    public func mergedSummary(_ merge: ThreadMerge, _ summary: String) async -> String {
        var current = summary
        for hook in hooks {
            let before = current
            // @dl:accept -- each hook point asks its hooks the same way through HookDeadline.ask; the point, answer type and fallback are the data
            current = await HookDeadline.ask(
                hook,
                at: "thread.merged",
                clock: clock,
                orElse: before,
                timedOut: Self.unheard
            ) {
                await hook.threadMerged(merge, summary: before)
            }
        }
        return current
    }
}
