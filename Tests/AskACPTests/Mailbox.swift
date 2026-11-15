import Synchronization

/// What a test waits for without a clock: values posted from anywhere, taken one at a time in the order they were posted. A wait
/// ends with nil when the test is cancelled (its time limit), so a value that never comes fails the test instead of holding it.
final class Mailbox<Value: Sendable>: Sendable {
    private struct State {
        var posted: [Value] = []
        var waiting: [(ticket: Int, continuation: CheckedContinuation<Value?, Never>)] = []
        var nextTicket = 0
    }

    private let state = Mutex(State())

    func post(_ value: Value) {
        let waiter = state.withLock { state -> CheckedContinuation<Value?, Never>? in
            guard !state.waiting.isEmpty else {
                state.posted.append(value)
                return nil
            }
            return state.waiting.removeFirst().continuation
        }
        waiter?.resume(returning: value)
    }

    /// The next value posted, awaited; nil when the task is cancelled first.
    func next() async -> Value? {
        let ticket = state.withLock { state -> Int in
            defer { state.nextTicket += 1 }
            return state.nextTicket
        }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let ready = state.withLock { state -> Value?? in
                    guard state.posted.isEmpty else { return state.posted.removeFirst() }
                    if Task.isCancelled { return .some(nil) }
                    state.waiting.append((ticket, continuation))
                    return nil
                }
                if let ready { continuation.resume(returning: ready) }
            }
        } onCancel: {
            let waiter = state.withLock { state -> CheckedContinuation<Value?, Never>? in
                guard let index = state.waiting.firstIndex(where: { $0.ticket == ticket }) else { return nil }
                return state.waiting.remove(at: index).continuation
            }
            waiter?.resume(returning: nil)
        }
    }
}
