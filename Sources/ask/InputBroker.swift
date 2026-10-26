internal import AskTUI
internal import Synchronization

/// Lines a running command asks the person for, and the answers: one continuation per question, resumed by the screen's answer or by the
/// command being cancelled, so a stopped sign-in never waits for a person who has gone (ADR-0117).
final class InputBroker: Sendable {
    private let state = Mutex(State())

    private struct State {
        var next = 0
        var waiting: [Int: CheckedContinuation<String?, Never>] = [:]
    }

    /// Asks `prompt` through `update` and waits. Nil when the person cancelled, or the command was.
    func ask(_ prompt: String, secret: Bool, update: @Sendable (ConversationUpdate) -> Void) async -> String? {
        let id = state.withLock { state -> Int in
            defer { state.next += 1 }
            return state.next
        }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                state.withLock { $0.waiting[id] = continuation }
                // Cancelled before the question could be registered: nobody will answer it.
                if Task.isCancelled {
                    resolve(id, nil)
                } else {
                    update(.askInput(id: id, prompt: prompt, secret: secret))
                }
            }
        } onCancel: {
            resolve(id, nil)
        }
    }

    /// The screen's answer to question `id`.
    func answer(_ id: Int, with text: String?) { resolve(id, text) }

    private func resolve(_ id: Int, _ text: String?) {
        let continuation = state.withLock { $0.waiting.removeValue(forKey: id) }
        continuation?.resume(returning: text)
    }
}
