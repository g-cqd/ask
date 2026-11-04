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
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            update(
                .notice(
                    "Usage: /thread TEXT starts a thread beside this conversation, which it knows up to now.",
                    isError: true
                )
            )
            return
        }
        do {
            let recorder = try threadSession()
            let name = threads.add(prompt: text, recorder: recorder)
            // Its conversation starts with its task; what is typed in its lane later, the screen shows as it is sent.
            update(.thread(id: name, .userPrompt(text)))
            update(
                .notice(
                    "Started \(name), which knows this conversation up to now. Open it from the job list (/jobs) or the sidebar to "
                        + "follow it and talk to it; when it ends, its answer goes with your next message.",
                    isError: false
                )
            )
            try runThread(name, text, update: update)
        } catch {
            update(.notice("Cannot start a thread: \(error)", isError: true))
        }
    }

    func sendToThread(_ id: String, text: String, update: @escaping @Sendable (ConversationUpdate) -> Void) {
        guard !threads.steer(id, with: text) else { return }
        do {
            try runThread(id, text, update: update)
        } catch {
            update(.thread(id: id, .notice("Cannot send to \(id): \(error)", isError: true)))
        }
    }

    func stopThreads() async { await threads.stopAll() }

    /// The thread's session: this one forked as it stands (what a running turn has written so far), or a new one before any prompt.
    private func threadSession() throws -> SessionRecorder {
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
        let queue = PromptQueue { [mcp] text in SessionTasks.attachReferences(await mcp.attachResources(text)) }
        let threads = threads
        let task = Task {
            let prompt = SessionTasks.attachReferences(await self.mcp.attachResources(text))
            let outcome: RunnerInfo.State
            do {
                try await loop.run(prompt, in: thread.recorder, input: queue) { event in
                    if let spent = event.usage {
                        self.usage.withLock { $0.addBeside(spent) }
                        update(.status(self.usage.withLock { $0.compact }))
                    }
                    for shown in Self.updates(for: event) { update(.thread(id: name, shown)) }
                }
                outcome = .done
            } catch AgentError.cancelled {
                outcome = .stopped
            } catch {
                update(.thread(id: name, .notice("\(name) stopped: \(error)", isError: true)))
                outcome = .failed
            }
            update(.thread(id: name, .runEnded))
            let answer = Self.lastAnswer(in: thread.recorder.tree)
            threads.ended(name, as: outcome, report: answer.map { Self.report(name, $0) })
            update(.runners(threads.runners))
            if let answer {
                let id = "\(name)-\(UUID().uuidString)"
                update(.asideStarted(id: id, question: thread.prompt, name: name))
                update(
                    .asideFinished(
                        id: id,
                        outcome == .done ? .succeeded : .failed("\(outcome.rawValue)"),
                        answer: answer
                    )
                )
                update(.notice("\(name)'s answer goes to the model with your next message.", isError: false))
            }
        }
        threads.run(name, task: task, queue: queue)
        update(.runners(threads.runners))
    }

    /// The text of the last reply in `tree`, nil when it has none.
    private static func lastAnswer(in tree: SessionTree) -> String? {
        for entry in tree.context().reversed() {
            guard case .response(let response, _) = entry.payload else { continue }
            let text = response.blocks.compactMap { if case .text(let text) = $0 { text } else { nil } }
                .joined(separator: "\n")
            if !text.allSatisfy(\.isWhitespace) { return text }
        }
        return nil
    }

    private static func report(_ name: String, _ answer: String) -> String {
        "\(ListReferences.threadMarker)\(name) ---\n\(answer)\n--- end of thread ---"
    }
}
