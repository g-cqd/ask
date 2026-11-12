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
        if let refusal = threadLimitReached(under: parent) {
            say(.notice(refusal, isError: true))
            return
        }
        // threads.model is resolved before the thread exists: one that does not resolve refuses it here, in what is shown.
        let loop: AgentLoop
        do { loop = try await threadLoop() } catch {
            let word =
                current.withLock { $0.settings.configuration.threads.value.threadModel } ?? "the conversation's model"
            say(.notice("Cannot start a thread: threads.model \"\(word)\" does not resolve: \(error)", isError: true))
            return
        }
        // The thread.start hook point: a hook may refuse it or rewrite its task.
        let prompt: String
        switch await loop.startingThread(ThreadStart(name: threads.nextName, parent: parent, prompt: text)) {
            case .refused(let reason):
                say(.notice(reason, isError: true))
                return
            case .start(let task): prompt = task
        }
        do {
            // Main's session first, so a thread started before any prompt is recorded there too (roadmap 0195).
            if parent == nil, session.withLock({ $0 == nil }) { _ = try recorder() }
            let recorder = try threadSession(from: parent)
            let name = threads.add(prompt: prompt, recorder: recorder, parent: parent)
            let source = parent.flatMap { threads.thread($0)?.recorder } ?? session.withLock { $0 }
            recordStarted(name, parent: parent, prompt: prompt, recorder: recorder, source: source)
            // Its conversation starts with its task; what is typed in its lane later, the screen shows as it is sent.
            update(.thread(id: name, .userPrompt(prompt)))
            // Where it starts, in the conversation it was forked from (note n23).
            say(.threadStarted(id: "fork-\(name)", name: name, prompt: prompt))
            runThread(name, prompt, update: update)
            nameThread(name, task: prompt, update: update)
        } catch {
            say(.notice("Cannot start a thread: \(error)", isError: true))
        }
    }

    /// Why a thread may not start under `parent` (main when nil), or nil when it may: `threads.max` at work, or `threads.depth` deep.
    func threadLimitReached(under parent: String?) -> String? {
        let limits = current.withLock { $0.settings.configuration.threads.value }
        // The more particular reason first: inside a thread that deep, no count of threads would let one start.
        if let parent, threads.depth(of: parent) >= limits.nesting {
            return "Threads nest at most \(limits.nesting) deep (threads.depth); \(parent) is that deep already."
        }
        let working = threads.working
        if working >= limits.atOnce {
            return
                "\(working) \(working == 1 ? "thread is" : "threads are") at work, as many as threads.max allows. Wait for "
                + "one to finish, or stop one (Ctrl+C in its lane)."
        }
        return nil
    }

    /// Names thread `name` from its task by the model `threads.names` asks for, when it answers in time; a name given by `/rename` first
    /// stays.
    private func nameThread(_ name: String, task: String, update: @escaping @Sendable (ConversationUpdate) -> Void) {
        guard namingEnabled else { return }
        Task {
            guard let title = await chosenName(for: task), threads.thread(name)?.title == nil else { return }
            renameThread(name, to: title, update: update)
        }
    }

    /// Names thread `id` `title` where it is shown, and records it for a resume.
    func renameThread(_ id: String, to title: String, update: @escaping @Sendable (ConversationUpdate) -> Void) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard threads.thread(id) != nil, !title.isEmpty else { return }
        threads.rename(id, to: title)
        try? session.withLock { $0 }?.recordThread(.renamed(id, to: title))
        update(.runners(threads.runners))
    }

    /// Ctrl+C in thread `id`'s lane (roadmap 0195): it stops with the threads under it, and asks once whether to merge them back in.
    func stopThread(_ id: String, update: @escaping @Sendable (ConversationUpdate) -> Void) {
        Task { await stopThread(id, update: update) }
    }

    /// Keeps which thread's lane is shown, for `/reload`; a job's lane, or main, is none.
    func laneShown(_ id: String?) {
        focusedThread.withLock { $0 = id.flatMap { threads.thread($0) == nil ? nil : $0 } }
    }

    func sendToThread(_ id: String, text: String, update: @escaping @Sendable (ConversationUpdate) -> Void) {
        sendToThread(id, text: text, images: [], update: update)
    }

    func sendToThread(
        _ id: String,
        text: String,
        images: [ToolImage],
        update: @escaping @Sendable (ConversationUpdate) -> Void
    ) {
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
        let parts = images.map(\.part)
        guard !threads.steer(id, with: text, images: parts) else { return }
        runThread(id, text, images: parts, update: update)
    }

    func stopThreads() async { await threads.stopAll() }

    /// The thread's session: `parent`'s, or this one, forked as it stands (what a running turn has written so far); or a new one
    /// before any prompt.
    private func threadSession(from parent: String?) throws -> SessionRecorder {
        if let parent, let thread = threads.thread(parent) {
            return try forked(thread.recorder, upTo: thread.recorder.tree.leaf)
        }
        if let original = session.withLock({ $0 }) { return try forked(original, upTo: original.tree.leaf) }
        return try newSession()
    }

    /// Runs `text` in thread `name`, its events drawn in its conversation, then reports its answer to main.
    func runThread(
        _ name: String,
        _ text: String,
        images: [ImagePart] = [],
        update: @escaping @Sendable (ConversationUpdate) -> Void
    ) {
        guard let thread = threads.thread(name) else { return }
        let threads = threads
        // What threads under it merged goes with what it is sent next, as main's do.
        let queue = PromptQueue { [mcp, self] text in
            threads.attachReports(
                await self.attachingForgeReferences(SessionTasks.attachReferences(await mcp.attachResources(text))),
                for: name
            )
        }
        let task = Task {
            let prompt = threads.attachReports(
                await self.attachingForgeReferences(
                    SessionTasks.attachReferences(await self.mcp.attachResources(text))
                ),
                for: name
            )
            let outcome: RunnerInfo.State
            do {
                // Its own model's loop when threads.model names one, a subagent's when it is one (roadmap 0063); a model that does
                // not resolve fails it here.
                let loop =
                    try await threads.isSubagent(name)
                    ? self.subagentLoop(for: threads.subagentDefinition(name)) : self.threadLoop()
                let route = ApprovalRoute(
                    send: { update(.thread(id: name, $0)) },
                    waiting: { began in
                        threads.asking(name, began: began)
                        update(.runners(threads.runners))
                    }
                )
                // What it asks goes to its lane, and the jobs its commands start are listed under it.
                try await JobOwner.$current.withValue(name) {
                    try await ApprovalRoute.$current.withValue(route) {
                        try await loop.run(prompt, images: images, in: thread.recorder, input: queue) { event in
                            if let spent = event.usage {
                                self.usage.withLock { $0.addBeside(spent) }
                                update(.status(self.usage.withLock { $0.compact }))
                            }
                            for shown in Self.updates(for: event) { update(.thread(id: name, shown)) }
                        }
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
