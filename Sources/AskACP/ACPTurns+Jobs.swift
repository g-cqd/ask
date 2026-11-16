internal import AemiJSON
internal import AskTUI
internal import Synchronization

/// The commands that go on after their calls have ended: the session's, not a turn's, since one outlives the turn that
/// started it.
extension ACPTurns {
    /// One job being watched: which watch of the session it is, and the task that tells the client.
    struct Watch {
        let number: Int
        let telling: Task<Void, Never>
    }

    /// Tells the client what `job` prints from now on, on the call `call` that started it, until the job ends: during the
    /// turn, between turns, in a later one. A job a later call reports again is told on that call.
    func watch(_ job: String, startedBy call: String, client: ACPClient) {
        // Each snapshot is the whole of what is kept of the output: one not yet sent is replaced by the next.
        let (snapshots, feed) = AsyncStream<JobUpdate>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let watching = session.conversation.watchJob(job) { feed.yield($0) }
        let number = state.withLock { state in
            state.watches += 1
            return state.watches
        }
        let telling = Task { [weak self, session] in
            var output = ACPJobOutput(call: call)
            for await snapshot in snapshots {
                if let update = output.update(for: snapshot) {
                    await client.notify(["sessionId": .string(session.id), "update": update])
                }
                if snapshot.status != .running { break }
            }
            watching.cancel()
            self?.state
                .withLock { state in
                    if state.watching[job]?.number == number { state.watching[job] = nil }
                }
        }
        let replaced = state.withLock { state in
            let replaced = state.watching[job]
            state.watching[job] = Watch(number: number, telling: telling)
            return replaced
        }
        replaced?.telling.cancel()
    }

    /// Stops telling of every job: the client has gone. The jobs themselves are the conversation's.
    func stopWatching() {
        let watched = state.withLock { state in
            defer { state.watching = [:] }
            return state.watching.values.map(\.telling)
        }
        for telling in watched { telling.cancel() }
    }
}
