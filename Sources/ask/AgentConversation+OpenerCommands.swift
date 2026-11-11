internal import AskAgentCore
internal import AskTUI
internal import AskTools
internal import Foundation
internal import Synchronization

/// Running the command an opener names for a clicked link (roadmap 0216, ADR-0148): asked first, unless the person allowed it always
/// or runs everything unasked; then started with its arguments as they are, no shell between.
extension AgentConversation {
    func runOpener(for uri: String, update: @escaping @Sendable (ConversationUpdate) -> Void) {
        let settings = current.withLock { $0.settings }
        let openers = settings.configuration.openers.value
        guard
            let link = ClickedLink(
                uri: uri,
                isDirectory: { path in
                    var isDirectory: ObjCBool = false
                    return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
                        && isDirectory.boolValue
                }
            ), case .command(let arguments, let index) = OpenerChoice.choose(for: link, in: openers),
            let rule = openers.rules?[index]
        else { return }
        // Not the turn's task: a click is the person's, whatever the model is doing, and Esc stops the turn, not this.
        Task {
            guard await self.allows(rule, arguments: arguments, policy: settings.approvalPolicy, update: update) else {
                return update(.notice("Not run: \(OpenerRun.shown(arguments))", isError: false))
            }
            let outcome = await OpenerLaunch.run(
                arguments,
                environment: settings.commandEnvironment.filtered(LaunchEnvironment.values),
                workingDirectory: settings.workspace
            )
            switch outcome {
                case .finished, .running: break
                case .exited(let status):
                    update(
                        .notice("Your opener ended with status \(status): \(OpenerRun.shown(arguments))", isError: true)
                    )
                case .failed(let reason):
                    update(.notice("Your opener did not run: \(reason).", isError: true))
            }
        }
    }

    /// Whether `rule`'s command may run now: allowed already, or asked and answered. "Always" is kept in ask's state.
    private func allows(
        _ rule: OpenerRule,
        arguments: [String],
        policy: ApprovalPolicy,
        update: @escaping @Sendable (ConversationUpdate) -> Void
    ) async -> Bool {
        let path = OpenerGrants.path(environment: LaunchEnvironment.values)
        var grants = OpenerGrants()
        // A store that cannot be read allows nothing, and is said: the question is asked as if nothing had been allowed.
        do { grants = try OpenerGrants.load(path) } catch { update(.notice("\(error)", isError: true)) }
        guard case .ask(let remembers) = OpenerRun.decide(rule, policy: policy, grants: grants) else { return true }
        let id = approvals.withLock { state in
            state.nextID += 1
            return state.nextID
        }
        let choice = await withCheckedContinuation { (answer: CheckedContinuation<ApprovalChoice, Never>) in
            approvals.withLock { $0.openers[id] = answer }
            update(
                .askApproval(
                    id: id,
                    question: "Run your opener for \(rule.matchDescription)?",
                    kind: .opener(remembers: remembers),
                    detail: OpenerRun.shown(arguments)
                )
            )
        }
        if choice == .session {
            // Read again: another ask may have allowed something since the question went up.
            var latest = (try? OpenerGrants.load(path)) ?? grants
            latest.allow(rule)
            do { try latest.save(to: path) } catch {
                update(.notice("Allowed this time; it could not be kept: \(error)", isError: true))
            }
        }
        return choice != .deny
    }
}
