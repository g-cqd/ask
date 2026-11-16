internal import AemiJSON
internal import AskTUI
internal import Synchronization

/// What happens during a turn besides its reading: the client is asked, a prompt sent meanwhile is taken or refused, a
/// compaction is given its id, and what is said after the turn's end is sorted.
extension ACPTurns {
    /// Whether a turn runs in the session now.
    var isRunning: Bool { state.withLock { $0.running } }

    /// An id for a compaction, never given twice in the session.
    func nextCompactionID() -> String {
        state.withLock { state in
            state.compactions += 1
            return "compaction-\(state.compactions)"
        }
    }

    /// What the conversation says once its turn has been answered: the name it was given meanwhile is still the session's
    /// title. Anything else said late (the git state read again, a list) was the screen's.
    static func late(_ update: ConversationUpdate, of session: ACPSession, to client: ACPClient) {
        for update in update.flattened {
            guard case .conversationName = update, let payload = ACPUpdate.payload(for: update) else { continue }
            Task { await client.notify(["sessionId": .string(session.id), "update": payload]) }
        }
    }

    /// Asks the client what only its person can answer (a permission, a form), and stops waiting for the answer when the turn is
    /// cancelled: nil then, as when it gives none.
    func asking(_ ask: @escaping @Sendable () async -> JSON?) async -> JSON? {
        let asking = Task { await ask() }
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
