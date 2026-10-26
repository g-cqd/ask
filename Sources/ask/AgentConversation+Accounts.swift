internal import AskAI
internal import AskTUI
internal import Foundation

/// `/login` and `/logout`: sign in to any provider, or out of any account, without leaving the conversation (ADR-0117). They are the same
/// code as `ask login` and `ask logout`, over the screen instead of the terminal.
extension AgentConversation {
    func answer(input id: Int, with text: String?) { inputs.answer(id, with: text) }

    /// `/login [PROVIDER] [api-key|device]`, or `/login custom NAME URL`.
    func login(arguments: String, update: @escaping @Sendable (ConversationUpdate) -> Void) async {
        let words = arguments.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else {
            update(
                .notice(
                    "Choose what to sign in to: type /login and pick from the list. " + LoginChoices.usage,
                    isError: false))
            return
        }
        let request: LoginRequest
        do { request = try LoginRequest(words: words) } catch {
            update(.notice("Not signed in: \(error). \(LoginChoices.usage)", isError: true))
            return
        }
        let interaction = ScreenInteraction(broker: inputs, update: update)
        do {
            let said = try await AccountLogin(interaction: interaction, environment: LaunchEnvironment.values)
                .run(request)
            update(.notice(said, isError: false))
        } catch let failure as AccountLogin.Failure where failure.cancelled {
            update(.notice("Sign-in cancelled.", isError: false))
            return
        } catch {
            update(
                .notice(Task.isCancelled ? "Sign-in stopped." : "Sign-in failed: \(error)", isError: !Task.isCancelled))
            return
        }
        // A sign-in can make a provider available that nothing named: the settings are read again, so the run follows it.
        await refreshSettings(update: update)
        update(.fillDraft("/model "))
    }

    /// `/logout [TARGET]`: forgets one account, or all of them with `/logout all`.
    func logout(arguments: String, update: @Sendable (ConversationUpdate) -> Void) async {
        let target = arguments.trimmingCharacters(in: .whitespaces)
        guard !target.isEmpty else {
            update(
                .notice(
                    "Choose what to sign out of: type /logout and pick from the list, or /logout all.", isError: false))
            return
        }
        do {
            let said = try AccountLogout(environment: LaunchEnvironment.values).run(target == "all" ? nil : target)
            update(.notice(said, isError: false))
        } catch {
            update(.notice("Not signed out: \(error)", isError: true))
            return
        }
        // Signed out of what was in use, the run moves to what is left, and says so; the conversation is not ended.
        await refreshSettings(update: update)
    }
}
