/// The keys' questions on the terminal ask was started from: `[y/N]`, a choice by its first letter, the capital one on Return.
struct TerminalSetupInteraction: SetupInteraction {
    private let terminal = CommandLineInteraction()

    // @dl:accept -- the terminal and the screen implement one protocol: their say and ask forward to each side's own interaction
    func say(_ text: String) { terminal.say(text) }

    func ask(_ prompt: String, secret: Bool) async -> String? { await terminal.ask(prompt, secret: secret) }

    func showOnce(_ text: String) async { _ = await terminal.ask(text, secret: true) }

    func choose(_ question: String, header: String, _ choices: [String], fallback: Int) async -> Int? {
        let letters = choices.enumerated()
            .map { index, choice in
                let letter = choice.prefix(1).lowercased()
                return index == fallback ? letter.uppercased() : letter
            }
        guard
            let reply = await terminal.ask("\(question) [\(letters.joined(separator: "/"))]", secret: false)?
                .lowercased(),
            let first = reply.first
        else { return fallback }
        return choices.firstIndex { $0.lowercased().first == first } ?? fallback
    }
}
