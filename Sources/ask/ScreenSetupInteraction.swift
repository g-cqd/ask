internal import AskAgentCore
internal import AskTUI

/// The keys' questions inside the screen (idea i1): what sign-in's ``ScreenInteraction`` says and asks, plus choices in the question
/// picker and a secret shown once. A closed question, or a screen that closes, answers nil.
struct ScreenSetupInteraction: SetupInteraction {
    let conversation: AgentConversation
    let update: @Sendable (ConversationUpdate) -> Void

    private var screen: ScreenInteraction { ScreenInteraction(broker: conversation.inputs, update: update) }

    // @dl:accept -- the terminal and the screen implement one protocol: their say and ask forward to each side's own interaction
    func say(_ text: String) { screen.say(text) }

    func ask(_ prompt: String, secret: Bool) async -> String? { await screen.ask(prompt, secret: secret) }

    func showOnce(_ text: String) async {
        _ = await conversation.inputs.ask(text, secret: true, transient: true, update: update)
    }

    func choose(_ question: String, header: String, _ choices: [String], fallback: Int) async -> Int? {
        let asked = PersonQuestion(
            question: question,
            header: header,
            choices: choices.map { PersonQuestion.Choice(label: $0) },
            note: .none
        )
        // Answered with nothing chosen is Return alone: the fallback, as on the terminal.
        guard let answers = await conversation.askPerson([asked], via: update) else { return nil }
        return answers.first?.chosen.first ?? fallback
    }
}
