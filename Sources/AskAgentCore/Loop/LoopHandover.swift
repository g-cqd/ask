internal import Foundation
internal import Synchronization

/// Where a running turn finds the loop to continue with (roadmap 0113): a model, effort or settings change made while the turn runs is
/// offered here, and the turn takes it before its next request, or ends a retry's wait to take it. The newest offer wins; one not taken
/// before the turn ends is taken by the next turn's first request.
public final class LoopHandover: Sendable {
    private struct State {
        var offered: AgentLoop?
        var waiters: [UUID: CheckedContinuation<Void, Never>] = [:]
    }

    private let state = Mutex(State())

    /// An empty handover.
    public init() {}

    /// Offers `loop` to the running turn, replacing an offer not taken yet, and wakes a retry waiting.
    public func offer(_ loop: AgentLoop) {
        let waiters = state.withLock { state in
            state.offered = loop
            defer { state.waiters = [:] }
            return Array(state.waiters.values)
        }
        for waiter in waiters { waiter.resume() }
    }

    /// The loop offered and not taken yet; taking it empties the handover.
    func take() -> AgentLoop? {
        state.withLock { state in
            defer { state.offered = nil }
            return state.offered
        }
    }

    /// Whether a loop is waiting to be taken.
    var isPending: Bool { state.withLock { $0.offered != nil } }

    /// Returns when a loop is offered, at once when one already is, or when the task is cancelled.
    func offered() async {
        let id = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let ready = state.withLock { state in
                    guard state.offered == nil, !Task.isCancelled else { return true }
                    state.waiters[id] = continuation
                    return false
                }
                if ready { continuation.resume() }
            }
        } onCancel: {
            state.withLock { $0.waiters.removeValue(forKey: id) }?.resume()
        }
    }
}
