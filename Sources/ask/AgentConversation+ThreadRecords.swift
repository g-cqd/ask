internal import AskAgentCore
internal import AskTUI
internal import Foundation
internal import Synchronization
internal import System

/// Threads kept with the session (roadmap 0195, step 3): main's session records where each thread started and where it merged, a
/// thread's own session says whose it is, and a resume rebuilds the tree from them. Merged threads come back read-only; the others come
/// back stopped, never restarted, and continue when something is typed in their lane.
extension AgentConversation {
    /// Records that `name` started over `recorder`, forked from `source` (main's session, or its parent thread's) at its leaf.
    func recordStarted(
        _ name: String,
        parent: String?,
        prompt: String,
        recorder: SessionRecorder,
        source: SessionRecorder?
    ) {
        guard let main = session.withLock({ $0 }) else { return }
        try? main.recordThread(
            .started(name, parent: parent, prompt: prompt, file: recorder.path, at: source?.tree.leaf)
        )
        try? recorder.recordThread(.identity(name, of: main.path))
    }

    /// Records that `name` merged, with `summary`, at the leaf of the conversation it merged into.
    func recordMerged(_ name: String, summary: String, into parent: SessionRecorder?) {
        guard let main = session.withLock({ $0 }) else { return }
        try? main.recordThread(.merged(name, summary: summary, at: (parent ?? main).tree.leaf))
    }

    /// Empties the thread table, stopping what runs there, and rebuilds it from the active session's records: what the screen needs to
    /// list each thread and show its conversation, with the blocks of the threads under it.
    func restoreThreads() -> [ConversationUpdate] {
        threads.reset()
        guard let main = session.withLock({ $0 }) else { return [.runners(threads.runners)] }
        let records = main.tree.threads
        var shown: [ConversationUpdate] = []
        for record in records where record.event == .started {
            guard let file = record.file,
                let recorder = try? SessionRecorder(
                    SessionFile.open(at: FilePath(file), keyring: SessionKeyAccess.keyring)
                )
            else {
                shown.append(.notice("\(record.id)'s session could not be opened; it is left out.", isError: true))
                continue
            }
            let merged = records.contains { $0.event == .merged && $0.id == record.id }
            threads.restore(
                record.id,
                prompt: record.prompt ?? "",
                parent: record.parent,
                recorder: recorder,
                state: merged ? .merged : .stopped
            )
            let lane = replayed(
                recorder.tree.activeBranch(),
                after: record.at,
                placing: Self.threadBlocks(records, under: record.id)
            )
            shown += lane.map { .thread(id: record.id, $0) }
        }
        return [.runners(threads.runners)] + shown
    }

    /// `branch` from the entry after `start` (all of it when nil or not on it), as the screen shows it, each block after the entry it
    /// names (a block naming none comes first; one naming an entry not shown is left out).
    func replayed(
        _ branch: [SessionEntry],
        after start: EntryID?,
        placing blocks: [(at: EntryID?, update: ConversationUpdate)]
    ) -> [ConversationUpdate] {
        let first = start.flatMap { id in branch.firstIndex { $0.id == id }.map { $0 + 1 } } ?? 0
        var updates = blocks.filter { $0.at == nil }.map(\.update)
        var pending: [SessionEntry] = []
        func flush() {
            for step in SessionReplay.steps(pending) {
                switch step {
                    case .prompt(let text): updates.append(.userPrompt(text))
                    case .event(let event):
                        recordUsage(event)
                        updates += Self.updates(for: event)
                }
            }
            pending = []
        }
        for entry in branch[first...] {
            pending.append(entry)
            let here = blocks.filter { $0.at == entry.id }
            if !here.isEmpty {
                flush()
                updates += here.map(\.update)
            }
        }
        flush()
        return updates
    }

    /// The blocks the threads under `parent` (main when nil) leave in its conversation: where each started, and where each merged.
    static func threadBlocks(_ records: [ThreadRecord], under parent: String?) -> [(
        at: EntryID?, update: ConversationUpdate
    )] {
        let started = records.filter { $0.event == .started && $0.parent == parent }
        let prompts = Dictionary(started.map { ($0.id, $0.prompt ?? "") }, uniquingKeysWith: { first, _ in first })
        // In the order they were recorded, which is the order they happened: blocks after one entry keep it.
        return records.compactMap { record in
            guard let prompt = prompts[record.id] else { return nil }
            switch record.event {
                case .started:
                    return (record.at, .threadStarted(id: "fork-\(record.id)", name: record.id, prompt: prompt))
                case .merged:
                    let merged = ConversationUpdate.threadMerged(
                        id: "merge-\(record.id)",
                        name: record.id,
                        prompt: prompt,
                        summary: record.summary ?? ""
                    )
                    return (record.at, merged)
                case .identity: return nil
            }
        }
    }
}
