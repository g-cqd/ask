internal import AemiSearch
internal import AskAI
internal import AskAgentCore
internal import AskTUI
internal import Foundation
internal import Synchronization

/// `/goal` (roadmap 0227): the conversation's goal, its judge on the provider's cheap model, and the person asked at a bound.
extension AgentConversation {
    /// How long the person has to say whether a goal goes on past its bound.
    static let goalBoundWait: Duration = .seconds(120)
    /// The most of the run the judge reads, from its end.
    static let goalRecentCharacters = 16_000

    /// `/goal CONDITION` sets the goal and sends it as the next message; `/goal` shows it; `/goal clear` drops it.
    func goalCommand(_ arguments: String, update: @escaping @Sendable (ConversationUpdate) -> Void) {
        let condition = arguments.trimmingCharacters(in: .whitespacesAndNewlines)
        switch condition {
            case "": update(.notice(Self.describe(goal.goal), isError: false))
            case "clear", "off", "stop":
                let ended = goal.end(.cleared)
                update(.notice(ended.map { "Goal cleared: \($0.condition)" } ?? "No goal is set.", isError: false))
            default:
                goal.set(condition)
                update(
                    .notice(
                        "Goal set: \(condition)\nJudged when each run ends; /goal shows it, /goal clear drops it.",
                        isError: false
                    )
                )
                // Sent once this command's run has ended, so it starts a turn rather than waiting in the editor.
                let directive =
                    "Goal: \(condition)\n\nWork toward it until it holds. When you believe it does, show the evidence in this "
                    + "conversation (run the check that proves it): a separate judge reads what you show."
                Task {
                    try? await Task.sleep(for: .milliseconds(50))
                    update(.submitPrompt(directive))
                }
        }
    }

    /// The goal's hook for `settings`' loop.
    func goalHook(_ settings: RunSettings) -> GoalHook {
        GoalHook(
            state: goal,
            judge: { [weak self] question in await self?.judgeGoal(question, settings: settings) },
            recent: { [weak self] in self?.recentForJudge() ?? "" },
            atBound: { [weak self] bound in await self?.goesOnPastBound(bound) ?? false },
            notice: { [weak self] text in self?.approvals.withLock { $0.ask }?(.notice(text, isError: false)) }
        )
    }

    /// One request to the provider's cheap model (the session's model when it lists none).
    private func judgeGoal(_ question: String, settings: RunSettings) async -> String? {
        let provider = settings.model.connection?.name ?? settings.model.providerName
        let listed = await ModelChoices.listed(provider: provider, environment: LaunchEnvironment.values)
        var model = settings.model
        if let cheap = ModelResolution.cheapModel(in: listed),
            let found = try? await self.settings(forModel: provider + "/" + cheap)
        {
            model = found.model
        }
        return await OneShotReply.text(
            question,
            by: makeProvider(model, transport: URLSessionTransport()),
            model: model.model,
            maxTokens: 400,
            within: .seconds(60)
        )
    }

    /// The session's recent entries as text, oldest first, the most recent kept whole up to ``goalRecentCharacters``.
    private func recentForJudge() -> String {
        guard let entries = session.withLock({ $0?.tree.entries }) else { return "" }
        var kept: [String] = []
        var size = 0
        for entry in entries.reversed() {
            for document in SessionSearchDocuments.documents(of: entry, time: 0).reversed() {
                let text =
                    document.text.count > 1_500 ? String(document.text.prefix(1_500)) + " [clipped]" : document.text
                let line = (document.fields["kind"] ?? "") + ": " + text
                guard size + line.count <= Self.goalRecentCharacters else {
                    return kept.reversed().joined(separator: "\n\n")
                }
                kept.append(line)
                size += line.count
            }
        }
        return kept.reversed().joined(separator: "\n\n")
    }

    /// Asks the person whether the goal goes on past `bound`; no answer within ``goalBoundWait`` is a no.
    private func goesOnPastBound(_ bound: String) async -> Bool {
        let question = PersonQuestion(
            question: "The goal reached its bound (\(bound)) without being met. Keep going for as much again?",
            header: "Goal",
            choices: [.init(label: "Keep going"), .init(label: "Stop the goal")],
            note: .none
        )
        let answer = await withTaskGroup(of: [PersonAnswer]?.self) { group in
            group.addTask { [weak self] in await self?.askPerson([question]) }
            group.addTask {
                try? await Task.sleep(for: Self.goalBoundWait)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        return answer?.first?.chosen == [0]
    }

    static func describe(_ goal: GoalState.Goal?) -> String {
        guard let goal else { return "No goal is set. /goal CONDITION sets one." }
        let minutes = Int((ContinuousClock.now - goal.started).components.seconds / 60)
        let state: String =
            switch goal.outcome {
                case nil: "active"
                case .met: "met"
                case .impossible(let why): "judged impossible: \(why)"
                case .stoppedAtBound: "stopped at its bound"
                case .cleared: "cleared"
            }
        return "Goal (\(state)): \(goal.condition)\n\(goal.turns) of \(goal.maxTurns) turns judged, \(minutes) min"
            + (goal.lastReason.map { "\nLast: \($0)" } ?? "")
    }
}
