internal import AemiJSON
internal import AemiJSONRPC
internal import AskTUI
internal import Synchronization

/// The turns of one session (ACP v1, Prompt Turn): a `session/prompt` starts one, its updates go to the client as they come, and
/// the request is answered when the turn ends, after the last of them.
///
/// A prompt that arrives while a turn runs steers it, as Enter does on the screen (ADR-0154), and is answered when that turn
/// ends. One the turn did not take before it ended is not lost: it starts the next turn, as the screen starts the copy it kept.
final class ACPTurns: Sendable {
    typealias Outcome = Result<JSONValue, JSONRPCError>
    typealias Notify = @Sendable (JSONValue) async -> Void

    /// A prompt waiting for its answer: the turn's own, or one sent during it.
    private struct Waiting {
        let id: Int
        let text: String
        var taken = false
        let reply: CheckedContinuation<Outcome, Never>
    }

    private struct State {
        var running = false
        var nextID = 1
        var during: [Waiting] = []
    }

    private let session: ACPSession
    private let state = Mutex(State())

    init(session: ACPSession) { self.session = session }

    /// `session/prompt`: the answer, when the turn `text` started or steered has ended.
    func prompt(_ text: String, notify: @escaping Notify) async -> Outcome {
        await withCheckedContinuation { reply in
            let steering = state.withLock { state -> Int? in
                defer { state.nextID += 1 }
                guard state.running else {
                    state.running = true
                    return nil
                }
                state.during.append(Waiting(id: state.nextID, text: text, reply: reply))
                return state.nextID
            }
            if let steering {
                session.conversation.enqueue(text, id: steering, followUp: false)
            } else {
                Task { await self.run(startingWith: text, reply: reply, notify: notify) }
            }
        }
    }

    /// Runs turns until no prompt waits for one: the first, then one for each prompt a turn ended without taking.
    private func run(startingWith text: String, reply: CheckedContinuation<Outcome, Never>, notify: @escaping Notify)
        async
    {
        var (text, reply) = (text, reply)
        while true {
            let outcome = await turn(text, notify: notify)
            let failed = if case .failure = outcome { true } else { false }
            let (answered, next) = state.withLock { state -> ([Waiting], Waiting?) in
                // A turn that failed answers every prompt sent during it with the failure: the client holds their text.
                let left = failed ? [] : state.during.filter { !$0.taken }
                let answered = state.during.filter { waiting in !left.contains { $0.id == waiting.id } }
                state.during = Array(left.dropFirst())
                state.running = !left.isEmpty
                return (answered, left.first)
            }
            reply.resume(returning: outcome)
            for waiting in answered { waiting.reply.resume(returning: outcome) }
            guard let next else { return }
            (text, reply) = (next.text, next.reply)
            // The others it left behind steer the turn that now starts.
            for waiting in state.withLock({ $0.during }) {
                session.conversation.enqueue(waiting.text, id: waiting.id, followUp: false)
            }
        }
    }

    /// One turn, read to its end: each update sent before the next is read, so the client sees them in the order they were said.
    private func turn(_ text: String, notify: Notify) async -> Outcome {
        let (updates, feed) = AsyncStream<ConversationUpdate>.makeStream()
        _ = session.conversation.start(text) { feed.yield($0) }
        var failure: String?
        var failed = false
        // What the conversation says after the turn's end (the git state read again, a list read) is not the turn's: not read.
        reading: for await update in updates {
            for update in update.flattened {
                switch update {
                    case .runEnded:
                        feed.finish()
                        break reading
                    case .returnQueuedPrompts: failed = true
                    case .notice(let reason, isError: true): failure = reason
                    case .promptAccepted(let id, _): take(id)
                    case .promptRefused(let id): refuse(id, because: failure)
                    default:
                        guard let payload = ACPUpdate.payload(for: update) else { continue }
                        await notify(["sessionId": .string(session.id), "update": payload])
                }
            }
        }
        guard failed else { return .success(["stopReason": "end_turn"]) }
        return .failure(JSONRPCError(code: JSONRPCError.internalError, message: failure ?? "The turn failed."))
    }

    /// The turn took the prompt sent during it as `id`: it is answered when the turn ends.
    private func take(_ id: Int) {
        state.withLock { state in
            guard let index = state.during.firstIndex(where: { $0.id == id }) else { return }
            state.during[index].taken = true
        }
    }

    /// The conversation did not take the prompt sent as `id` (a skill it names cannot be loaded): its request says so.
    private func refuse(_ id: Int, because reason: String?) {
        let refused = state.withLock { state -> Waiting? in
            guard let index = state.during.firstIndex(where: { $0.id == id }) else { return nil }
            return state.during.remove(at: index)
        }
        refused?.reply.resume(returning: .failure(.invalidParams(reason ?? "the prompt was not taken")))
    }
}
