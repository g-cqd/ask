internal import AskTUI

/// A sign-in on the screen: what it says is a notice in the transcript, and what it asks is a question in the status line, answered in a
/// buffer that is not the draft, so a key is neither shown nor kept.
struct ScreenInteraction: SignInInteraction {
    let broker: InputBroker
    let update: @Sendable (ConversationUpdate) -> Void

    func say(_ text: String) { update(.notice(text, isError: false)) }

    func ask(_ prompt: String, secret: Bool) async -> String? {
        await broker.ask(prompt, secret: secret, update: update)
    }
}
