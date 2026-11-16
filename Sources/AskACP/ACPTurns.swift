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
    struct Waiting {
        /// Its place among the session's prompts, which is also the id the conversation knows it by.
        let sequence: Int
        let text: String
        /// The command it is, when it is one: it runs as a turn of its own, and steers none.
        let command: ACPCommands.Typed?
        var taken = false
        let reply: CheckedContinuation<Outcome, Never>
    }

    struct State {
        var running = false
        /// Whether the turn that runs is the model's, which a prompt sent during it steers; a command's takes none.
        var steered = false
        /// How many prompts were admitted, and through which of them the client has cancelled.
        var sequence = 0
        var cancelledThrough = 0
        var during: [Waiting] = []
        /// The conversation's run, while a turn is read, and the permission the client is being asked.
        var run: Task<Void, Never>?
        var asking: Task<JSON?, Never>?
        /// How many compactions the client was told of, this session: each has an id of its own.
        var compactions = 0
        /// The jobs whose output the client is told of, by job, and how many were ever watched (``watch(_:startedBy:client:)``).
        var watching: [String: Watch] = [:]
        var watches = 0

        /// What becomes of the prompt admitted as `sequence` as it arrives, which a turn that starts is noted by. A command
        /// steers nothing and is steered by nothing: it waits for the turn's end, and so does a prompt sent while one runs.
        mutating func place(_ sequence: Int, isCommand: Bool) -> Place {
            // Cancelled before its work began: it neither starts a turn nor steers one.
            if sequence <= cancelledThrough { return .cancelled }
            guard running else {
                (running, steered) = (true, !isCommand)
                return .starts
            }
            return !isCommand && steered ? .steers : .waits
        }
    }

    /// What becomes of a prompt as it arrives: it starts a turn, steers the one that runs, or waits for its end.
    enum Place { case cancelled, starts, steers, waits }

    static let cancelled: Outcome = .success(["stopReason": "cancelled"])

    let session: ACPSession
    let state = Mutex(State())

    init(session: ACPSession) { self.session = session }

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

    /// `session/prompt`: the answer, when the turn `text` started or steered has ended. A command (``ACPCommands``) is a turn of
    /// its own: sent during another, it runs when that one has ended.
    func prompt(_ text: String, admitted sequence: Int, client: ACPClient) async -> Outcome {
        await withCheckedContinuation { reply in
            let command = ACPCommands.typed(text, in: session.conversation)
            let waiting = Waiting(sequence: sequence, text: text, command: command, reply: reply)
            let place = state.withLock { state -> Place in
                let place = state.place(sequence, isCommand: command != nil)
                if place == .steers || place == .waits { state.during.append(waiting) }
                return place
            }
            switch place {
                case .cancelled: reply.resume(returning: Self.cancelled)
                case .steers: steer(waiting)
                case .starts: Task { await self.run(startingWith: waiting, client: client) }
                case .waits: break
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
                state.steered = left.first.map { $0.command == nil } ?? false
                return (answered, left.first)
            }
            current.reply.resume(returning: outcome)
            for waiting in answered { waiting.reply.resume(returning: outcome) }
            guard let next else { return }
            current = next
            // The others it left behind steer the turn that now starts, when it is the model's; the commands among them wait.
            guard next.command == nil else { continue }
            for waiting in state.withLock({ $0.during }) where waiting.command == nil {
                steer(waiting)
            }
        }
    }

    /// Offers a prompt sent during the model's turn to that turn.
    private func steer(_ waiting: Waiting) {
        let text = ACPCommands.prompt(waiting.text, in: session.conversation)
        session.conversation.enqueue(text, id: waiting.sequence, followUp: false)
    }

    /// One turn, read to its end: `cancelled` when the client cancelled its prompt, whatever the conversation then said, since a
    /// cancellation is never answered as an error (Prompt Turn, "Cancellation").
    private func turn(_ prompt: Waiting, client: ACPClient) async -> Outcome {
        let (updates, feed) = AsyncStream<ConversationUpdate>.makeStream()
        let said: @Sendable (ConversationUpdate) -> Void = { [session] update in
            if case .terminated = feed.yield(update) { Self.late(update, of: session, to: client) }
        }
        let run =
            if let command = prompt.command {
                session.conversation.command(command.name, arguments: command.arguments, update: said)
            } else {
                session.conversation.start(ACPCommands.prompt(prompt.text, in: session.conversation), update: said)
            }
        // A cancellation read between the prompt's admission and here found no run to stop.
        if state.withLock({ state in
            state.run = run
            return prompt.sequence <= state.cancelledThrough
        }) {
            run.cancel()
        }
        var reader = ACPTurnReader(session: session, client: client, answers: prompt.command != nil)
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
}
