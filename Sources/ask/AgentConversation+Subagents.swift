internal import AskAgentCore
internal import AskMCP
internal import AskTUI
internal import AskTools
internal import Foundation
internal import Synchronization
internal import System

/// Subagents (roadmap 0063, ADR-0146): threads the model starts with the `agent` tool. One sees only its task, works read-only unless
/// `agents.allowWrites`, cannot start one of its own, always merges on its own, and its summary is the call's result.
extension AgentConversation {
    /// Starts a subagent for `task` under the conversation whose tool asked (main, or a thread), and waits for its report.
    func startSubagent(_ task: SubagentTask) async -> SubagentOutcome {
        let parent = JobOwner.current
        guard current.withLock({ $0.settings.configuration.agents.value.isEnabled }) else {
            return .refused("agents.enabled is off.")
        }
        if let refusal = threadLimitReached(under: parent) { return .refused(refusal) }
        guard let update = approvals.withLock({ $0.ask }) else {
            return .refused("Nothing can show a subagent in this run.")
        }
        do { _ = try await subagentLoop(for: task.definition) } catch {
            return .refused("Its loop could not be built: \(error)")
        }
        let say: @Sendable (ConversationUpdate) -> Void = { shown in
            update(parent.map { .thread(id: $0, shown) } ?? shown)
        }
        let name: String
        do {
            if parent == nil, session.withLock({ $0 == nil }) { _ = try recorder() }
            let recorder = try newSession()
            name = threads.add(prompt: task.task, recorder: recorder, parent: parent)
            threads.markSubagent(name, definition: task.definition)
            let source = parent.flatMap { threads.thread($0)?.recorder } ?? session.withLock { $0 }
            recordStarted(name, parent: parent, prompt: task.task, recorder: recorder, source: source)
        } catch {
            return .refused("\(error)")
        }
        update(.thread(id: name, .userPrompt(task.prompt)))
        say(.threadStarted(id: "fork-\(name)", name: name, prompt: task.task, subagent: true))
        let threads = threads
        let summary = await withTaskCancellationHandler {
            await withCheckedContinuation { waiter in
                threads.wait(for: name, waiter)
                runThread(name, task.prompt, update: update)
            }
        } onCancel: {
            // The call that waits was stopped: so is the subagent, which then merges what it has.
            Task { await threads.stop([name], holding: false) }
        }
        return .report(name: name, summary: summary)
    }

    /// The loop subagents run on, as `definition` when there is one: `threads.model`'s or main's settings, writing nowhere unless
    /// `agents.allowWrites`, at most `agents.maxTurns` turns, no `agent` tool of its own, and only the definition's tools when it
    /// names some. Built once for each definition, dropped when the settings change.
    func subagentLoop(for definition: AgentDefinition?) async throws -> AgentLoop {
        let key = definition?.name ?? ""
        if let cached = current.withLock({ $0.subagentLoops[key] }) { return cached }
        var settings = current.withLock { $0.settings }
        if let word = settings.configuration.threads.value.threadModel {
            settings = try await self.settings(forModel: word)
        }
        let agents = settings.configuration.agents.value
        if !agents.writes { settings.sandbox.write = .roots([]) }
        settings.configuration.maxTurns.value = agents.turns
        settings.configuration.maxTurns.source = .flag("agents.maxTurns")
        mcp.apply(settings.configuration.mcp.value.servers)
        var hooks = loopHooks(settings, subagents: false)
        // A definition that names tools keeps only those; a name ask does not know grants nothing.
        if let definition, !definition.tools.isEmpty { hooks.keepTools = Set(definition.tools.compactMap(\.ask)) }
        let created = try makeLoop(settings, hooks)
        return current.withLock { current in
            if current.subagentLoops[key] == nil { current.subagentLoops[key] = created }
            return current.subagentLoops[key] ?? created
        }
    }

    /// A session of its own, with no conversation in it: a subagent's, or a thread's before any prompt.
    func newSession() throws -> SessionRecorder {
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
}
