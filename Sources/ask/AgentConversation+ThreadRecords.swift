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
        source: SessionRecorder?,
        subagent: String? = nil
    ) {
        guard let main = session.withLock({ $0 }) else { return }
        var started = ThreadRecord.started(
            name,
            parent: parent,
            prompt: prompt,
            file: recorder.path,
            at: source?.tree.leaf
        )
        // A subagent says so, and as which definition, so a resume brings it back as one (roadmap 0063 phase 5).
        started.subagent = subagent
        try? main.recordThread(started)
        try? recorder.recordThread(.identity(name, of: main.path))
    }

    /// Records that `name` merged, with `summary`, at the leaf of the conversation it merged into.
    func recordMerged(_ name: String, summary: String, into parent: SessionRecorder?) {
        guard let main = session.withLock({ $0 }) else { return }
        try? main.recordThread(.merged(name, summary: summary, at: (parent ?? main).tree.leaf))
    }

    /// Empties the thread table, stopping what runs there, and rebuilds it from the active session's records: what the screen needs to
    /// list each thread and show its conversation, with the blocks of the threads under it, and the conversation's name (note n60).
    func restoreThreads() -> [ConversationUpdate] {
        threads.reset()
        guard let main = session.withLock({ $0 }) else { return [.runners(threads.runners), .conversationName(nil)] }
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
            let title = records.last { $0.event == .renamed && $0.id == record.id }?.title
            threads.restore(
                record.id,
                prompt: record.prompt ?? "",
                parent: record.parent,
                recorder: recorder,
                state: merged ? .merged : .stopped
            )
            if let title { threads.rename(record.id, to: title) }
            // A subagent comes back as one: read-only, without an agent tool, as its definition if that still exists.
            if let definition = record.subagent {
                let workspace = current.withLock { $0.settings.workspace }
                let found =
                    definition.isEmpty ? nil : agentDefinitions(workspace: workspace).first { $0.name == definition }
                threads.markSubagent(record.id, definition: found)
            }
            let branch = recorder.tree.activeBranch()
            let lane = replayed(
                branch,
                after: record.at,
                placing: Self.threadBlocks(records, under: record.id, on: branch)
            )
            shown += lane.map { .thread(id: record.id, $0) }
        }
        return [.runners(threads.runners), .conversationName(main.tree.conversationName)] + shown
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

    /// The blocks the threads under `parent` (main when nil) leave in its conversation, `branch`: where each started, and where each
    /// merged, at the end of the turn its summary came in (``ThreadRecord/shown(in:)``).
    static func threadBlocks(_ records: [ThreadRecord], under parent: String?, on branch: [SessionEntry]) -> [(
        at: EntryID?, update: ConversationUpdate
    )] {
        let started = records.filter { $0.event == .started && $0.parent == parent }
        let prompts = Dictionary(started.map { ($0.id, $0.prompt ?? "") }, uniquingKeysWith: { first, _ in first })
        // In the order they were recorded, which is the order they happened: blocks after one entry keep it.
        return records.compactMap { record in
            guard let prompt = prompts[record.id] else { return nil }
            switch record.event {
                case .started:
                    return (
                        record.at,
                        .threadStarted(
                            id: "fork-\(record.id)",
                            name: record.id,
                            prompt: prompt,
                            subagent: record.subagent != nil
                        )
                    )
                case .merged:
                    let merged = ConversationUpdate.threadMerged(
                        id: "merge-\(record.id)",
                        name: record.id,
                        prompt: prompt,
                        summary: record.summary ?? ""
                    )
                    return (record.shown(in: branch), merged)
                case .identity, .renamed: return nil
            }
        }
    }
}

/// `/threads` (roadmap 0195, note n22): every thread of the session, merged or not, to show one's lane.
extension AgentConversation {
    /// The threads as picker rows, in the order they started: name, state and task.
    func threadRows() -> [ChoiceRow] {
        threads.runners.filter { $0.kind == .agent }
            .map { ChoiceRow(label: $0.name, detail: "\($0.state.rawValue) · \($0.detail)", arguments: $0.id) }
    }

    /// With no argument the picker; with a thread's id or name, its lane.
    func showThreads(_ arguments: String, update: @escaping @Sendable (ConversationUpdate) -> Void) {
        let asked = arguments.trimmingCharacters(in: .whitespaces)
        let rows = threadRows()
        guard !asked.isEmpty else {
            update(
                rows.isEmpty
                    ? .notice("No threads in this session yet: /thread TEXT starts one.", isError: false)
                    : .batch([.choices(command: "threads", rows: rows), .fillDraft("/threads ")])
            )
            return
        }
        guard let row = rows.first(where: { $0.arguments == asked || $0.label == asked }) else {
            update(.notice("No thread \(asked) in this session; /threads lists them.", isError: true))
            return
        }
        update(.focusThread(id: row.arguments))
    }
}
