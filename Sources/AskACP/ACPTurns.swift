internal import AemiJSON
internal import AemiJSONRPC
internal import AskTUI
internal import Synchronization

/// The turns of one session (ACP v1, Prompt Turn): a `session/prompt` starts one, its updates go to the client as they come, and
/// the request is answered when the turn ends, after the last of them.
///
/// A prompt that arrives while a turn runs steers it, as Enter does on the screen (ADR-0154), and is answered when that turn
/// ends. One the turn did not take before it ended is not lost: it starts the next turn, as the screen starts the copy it kept.
///
/// `session/cancel` stops the turn as Esc does, and cancels every prompt the client had sent before it; one sent after it is
/// the next turn. Prompts and cancellations are numbered as the connection reads them (``admit()``, ``cancel()``), so a
/// cancellation written right behind its prompt finds it, whether or not its turn has begun.
final class ACPTurns: Sendable {
    typealias Outcome = Result<JSONValue, JSONRPCError>

    /// A prompt waiting for its answer: the turn's own, or one sent during it.
    private struct Waiting {
        /// Its place among the session's prompts, which is also the id the conversation knows it by.
        let sequence: Int
        let text: String
        var taken = false
        let reply: CheckedContinuation<Outcome, Never>
    }

    private struct State {
        var running = false
        /// How many prompts were admitted, and through which of them the client has cancelled.
        var sequence = 0
        var cancelledThrough = 0
        var during: [Waiting] = []
        /// The conversation's run, while a turn is read, and the permission the client is being asked.
        var run: Task<Void, Never>?
        var asking: Task<JSON?, Never>?
        /// How many compactions the client was told of, this session: each has an id of its own.
        var compactions = 0
    }

    private static let cancelled: Outcome = .success(["stopReason": "cancelled"])

    private let session: ACPSession
    private let state = Mutex(State())

    init(session: ACPSession) { self.session = session }

    /// An id for a compaction, never given twice in the session.
    func nextCompactionID() -> String {
        state.withLock { state in
            state.compactions += 1
            return "compaction-\(state.compactions)"
        }
    }

    /// Admits a prompt, where the connection reads it: its place among the session's prompts and cancellations.
    func admit() -> Int {
        state.withLock { state in
            state.sequence += 1
            return state.sequence
        }
    }

    /// `session/cancel`, where the connection reads it: every prompt admitted so far is cancelled, the turn that runs is
    /// stopped, and a permission still asked of the client is no longer waited for.
    func cancel() {
        let (run, asking) = state.withLock { state in
            state.cancelledThrough = state.sequence
            return (state.run, state.asking)
        }
        run?.cancel()
        asking?.cancel()
    }

    /// `session/prompt`: the answer, when the turn `text` started or steered has ended.
    func prompt(_ text: String, admitted sequence: Int, client: ACPClient) async -> Outcome {
        await withCheckedContinuation { reply in
            let waiting = Waiting(sequence: sequence, text: text, reply: reply)
            let steers = state.withLock { state -> Bool? in
                // Cancelled before its work began: it neither starts a turn nor steers one.
                if sequence <= state.cancelledThrough { return nil }
                guard state.running else {
                    state.running = true
                    return false
                }
                state.during.append(waiting)
                return true
            }
            switch steers {
                case nil: reply.resume(returning: Self.cancelled)
                case true?: session.conversation.enqueue(text, id: sequence, followUp: false)
                case false?: Task { await self.run(startingWith: waiting, client: client) }
            }
        }
    }

    /// Runs turns until no prompt waits for one: the first, then one for each prompt a turn ended without taking.
    private func run(startingWith first: Waiting, client: ACPClient) async {
        var current = first
        while true {
            let outcome = await turn(current, client: client)
            let (answered, next) = state.withLock { state -> ([Waiting], Waiting?) in
                let stopped = current.sequence <= state.cancelledThrough
                let failed = if case .failure = outcome { true } else { false }
                // A turn that failed answers every prompt sent during it with the failure: the client holds their text. One that
                // was cancelled answers those sent before the cancellation; a prompt sent after it is the next turn.
                let left = state.during.filter { waiting in
                    !failed && !waiting.taken && (!stopped || waiting.sequence > state.cancelledThrough)
                }
                let answered = state.during.filter { waiting in !left.contains { $0.sequence == waiting.sequence } }
                state.during = Array(left.dropFirst())
                state.running = !left.isEmpty
                return (answered, left.first)
            }
            current.reply.resume(returning: outcome)
            for waiting in answered { waiting.reply.resume(returning: outcome) }
            guard let next else { return }
            current = next
            // The others it left behind steer the turn that now starts.
            for waiting in state.withLock({ $0.during }) {
                session.conversation.enqueue(waiting.text, id: waiting.sequence, followUp: false)
            }
        }
    }

    /// One turn, read to its end: `cancelled` when the client cancelled its prompt, whatever the conversation then said, since a
    /// cancellation is never answered as an error (Prompt Turn, "Cancellation").
    private func turn(_ prompt: Waiting, client: ACPClient) async -> Outcome {
        let (updates, feed) = AsyncStream<ConversationUpdate>.makeStream()
        let run = session.conversation.start(prompt.text) { [session] update in
            if case .terminated = feed.yield(update) { Self.late(update, of: session, to: client) }
        }
        // A cancellation read between the prompt's admission and here found no run to stop.
        if state.withLock({ state in
            state.run = run
            return prompt.sequence <= state.cancelledThrough
        }) {
            run.cancel()
        }
        var reader = ACPTurnReader(session: session, client: client)
        // What the conversation says after the turn's end (the git state read again, a list read) is not the turn's: not read.
        reading: for await update in updates {
            for update in update.flattened where await !reader.read(update, in: self) {
                feed.finish()
                break reading
            }
        }
        await reader.end(in: self)
        let stopped = state.withLock { state in
            state.run = nil
            return prompt.sequence <= state.cancelledThrough
        }
        if stopped { return Self.cancelled }
        guard reader.failed else { return .success(["stopReason": "end_turn"]) }
        return .failure(JSONRPCError(code: JSONRPCError.internalError, message: reader.failure ?? "The turn failed."))
    }

    /// What the conversation says once its turn has been answered: the name it was given meanwhile is still the session's
    /// title. Anything else said late (the git state read again, a list) was the screen's.
    private static func late(_ update: ConversationUpdate, of session: ACPSession, to client: ACPClient) {
        for update in update.flattened {
            guard case .conversationName = update, let payload = ACPUpdate.payload(for: update) else { continue }
            Task { await client.notify(["sessionId": .string(session.id), "update": payload]) }
        }
    }

    /// Asks the client a permission, and stops waiting for its answer when the turn is cancelled: nil then, as when it gives none.
    func permission(_ params: JSONValue, from client: ACPClient) async -> JSON? {
        let asking = Task { await client.requestPermission(params) }
        if state.withLock({ state in
            state.asking = asking
            return state.run?.isCancelled == true
        }) {
            asking.cancel()
        }
        let answer = await asking.value
        state.withLock { $0.asking = nil }
        return answer
    }

    /// The turn took the prompt sent during it as `id`: it is answered when the turn ends.
    func take(_ id: Int) {
        state.withLock { state in
            guard let index = state.during.firstIndex(where: { $0.sequence == id }) else { return }
            state.during[index].taken = true
        }
    }

    /// The conversation did not take the prompt sent as `id` (a skill it names cannot be loaded): its request says so.
    func refuse(_ id: Int, because reason: String?) {
        let refused = state.withLock { state -> Waiting? in
            guard let index = state.during.firstIndex(where: { $0.sequence == id }) else { return nil }
            return state.during.remove(at: index)
        }
        refused?.reply.resume(returning: .failure(.invalidParams(reason ?? "the prompt was not taken")))
    }
}
