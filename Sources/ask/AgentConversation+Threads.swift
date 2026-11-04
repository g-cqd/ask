internal import AskAI
internal import AskAgentCore
internal import AskTUI
internal import AskTools
internal import Foundation
internal import Synchronization
internal import System

/// `/thread TEXT` (roadmap 0194, the owner's choices of 2026-11-03): a fork of the conversation as it stands, run beside it in this
/// process with everything main may use (its tools, sandbox and the session's grants), listed as a runner. Focusing its lane shows its
/// conversation, and what is typed there goes to it. When a run of it ends, its answer is shown in main and goes with the person's next
/// message, so the main model knows it.
extension AgentConversation {
    func startThread(_ text: String, update: @escaping @Sendable (ConversationUpdate) -> Void) async {
        await beginThread(text, parent: nil, update: update)
    }

    func startThread(_ text: String, from parent: String, update: @escaping @Sendable (ConversationUpdate) -> Void)
        async
    {
        await beginThread(text, parent: parent, update: update)
    }

    /// From `parent`, a thread forked from that thread's conversation and listed under it, its notices in that thread's lane.
    private func beginThread(
        _ text: String,
        parent: String?,
        update: @escaping @Sendable (ConversationUpdate) -> Void
    ) async {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let say: @Sendable (ConversationUpdate) -> Void = { shown in
            update(parent.map { .thread(id: $0, shown) } ?? shown)
        }
        guard !text.isEmpty else {
            say(
                .notice(
                    "Usage: /thread TEXT starts a thread beside this conversation, which it knows up to now.",
                    isError: true
                )
            )
            return
        }
        do {
            let recorder = try threadSession(from: parent)
            let name = threads.add(prompt: text, recorder: recorder, parent: parent)
            let source = parent.flatMap { threads.thread($0)?.recorder } ?? session.withLock { $0 }
            recordStarted(name, parent: parent, prompt: text, recorder: recorder, source: source)
            // Its conversation starts with its task; what is typed in its lane later, the screen shows as it is sent.
            update(.thread(id: name, .userPrompt(text)))
            // Where it starts, in the conversation it was forked from (note n23).
            say(.threadStarted(id: "fork-\(name)", name: name, prompt: text))
            try runThread(name, text, update: update)
        } catch {
            say(.notice("Cannot start a thread: \(error)", isError: true))
        }
    }

    /// Keeps which thread's lane is shown, for `/reload`; a job's lane, or main, is none.
    func laneShown(_ id: String?) {
        focusedThread.withLock { $0 = id.flatMap { threads.thread($0) == nil ? nil : $0 } }
    }

    func sendToThread(_ id: String, text: String, update: @escaping @Sendable (ConversationUpdate) -> Void) {
        // A merged thread is closed (roadmap 0195): its conversation stays readable, and `/thread` there branches from it.
        switch threads.thread(id)?.state {
            case .merged?:
                let shown =
                    "\(id) has merged; it is read-only now. /thread TEXT here starts a new thread from where it ended."
                update(.thread(id: id, .notice(shown, isError: false)))
                return
            case .merging?:
                update(.thread(id: id, .notice("\(id) is writing its summary to merge.", isError: false)))
                return
            default: break
        }
        guard !threads.steer(id, with: text) else { return }
        do {
            try runThread(id, text, update: update)
        } catch {
            update(.thread(id: id, .notice("Cannot send to \(id): \(error)", isError: true)))
        }
    }

    func stopThreads() async { await threads.stopAll() }

    /// The thread's session: `parent`'s, or this one, forked as it stands (what a running turn has written so far); or a new one
    /// before any prompt.
    private func threadSession(from parent: String?) throws -> SessionRecorder {
        if let parent, let thread = threads.thread(parent) {
            return try forked(thread.recorder, upTo: thread.recorder.tree.leaf)
        }
        if let original = session.withLock({ $0 }) { return try forked(original, upTo: original.tree.leaf) }
        try directory.create()
        let protection = SessionKeyAccess.protection
        let recorder = SessionRecorder(
            try SessionFile.create(
                at: FilePath(directory.newSessionPath()),
                format: protection.format,
                keyring: protection.keyring
            )
        )
        let settings = current.withLock { $0.settings }
        try recorder.select(SessionRouting.destination(settings.model), explicitlySelected: false)
        try settings.record(in: recorder)
        return recorder
    }

    /// Runs `text` in thread `name`, its events drawn in its conversation, then reports its answer to main.
    private func runThread(_ name: String, _ text: String, update: @escaping @Sendable (ConversationUpdate) -> Void)
        throws
    {
        guard let thread = threads.thread(name) else { return }
        let loop = try agentLoop()
        let threads = threads
        // What threads under it merged goes with what it is sent next, as main's do.
        let queue = PromptQueue { [mcp] text in
            threads.attachReports(SessionTasks.attachReferences(await mcp.attachResources(text)), for: name)
        }
        let task = Task {
            let prompt = threads.attachReports(
                SessionTasks.attachReferences(await self.mcp.attachResources(text)),
                for: name
            )
            let outcome: RunnerInfo.State
            do {
                let route = ApprovalRoute(
                    send: { update(.thread(id: name, $0)) },
                    waiting: { began in
                        threads.asking(name, began: began)
                        update(.runners(threads.runners))
                    }
                )
                try await ApprovalRoute.$current.withValue(route) {
                    try await loop.run(prompt, in: thread.recorder, input: queue) { event in
                        if let spent = event.usage {
                            self.usage.withLock { $0.addBeside(spent) }
                            update(.status(self.usage.withLock { $0.compact }))
                        }
                        for shown in Self.updates(for: event) { update(.thread(id: name, shown)) }
                    }
                }
                outcome = .done
            } catch AgentError.cancelled {
                outcome = .stopped
            } catch {
                update(.thread(id: name, .notice("\(name) stopped: \(error)", isError: true)))
                outcome = .failed
            }
            // A session switch stopped it, and its name may be another thread's now.
            guard threads.owns(name, thread.recorder) else { return }
            update(.thread(id: name, .runEnded))
            threads.ended(name, as: outcome)
            update(.runners(threads.runners))
            await self.settle(name, update: update)
        }
        threads.run(name, task: task, queue: queue)
        update(.runners(threads.runners))
    }
}
