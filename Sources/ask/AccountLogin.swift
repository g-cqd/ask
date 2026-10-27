internal import AskAI
internal import Foundation

/// Signs in to a provider, by account or by key, over whatever ``SignInInteraction`` the caller has: `ask login` on the terminal and `/login`
/// on the screen are the same code, so neither can offer a way the other lacks.
struct AccountLogin: Sendable {
    /// Why a sign-in did not finish, in words for the person.
    struct Failure: Error, CustomStringConvertible {
        let description: String
        /// Whether the person ended it, which is not a failure to report as one.
        let cancelled: Bool
        init(_ description: String, cancelled: Bool = false) {
            self.description = description
            self.cancelled = cancelled
        }

        /// Nothing was entered: the question was cancelled or the input ended.
        static let nothingEntered = Failure("nothing was entered.", cancelled: true)
    }

    let interaction: any SignInInteraction
    let environment: [String: String]
    let transport = URLSessionTransport()

    init(interaction: any SignInInteraction, environment: [String: String] = LaunchEnvironment.values) {
        self.interaction = interaction
        self.environment = environment
    }

    /// What a browser sign-in shows: the link, what to do there if it takes more than opening it, and that ask waits.
    func show(_ prompt: SignInPrompt) {
        var text = "Open this URL and sign in:\n\n  \(prompt.url.absoluteString)\n"
        if let instructions = prompt.instructions { text += "\n\(instructions)\n" }
        interaction.say(text + "\nWaiting for you to finish in the browser…")
    }

    var file: CredentialFile { CredentialFile.standard(environment: environment) }

    /// Signs in as `request` says.
    /// - Returns: a line saying who is signed in, for the person.
    /// - Throws: a ``Failure``, or the sign-in's own error, both of which print as sentences.
    func run(_ request: LoginRequest) async throws -> String {
        if request.usesTypedKey { return try await signInWithKey(request) }
        let connection = try request.connection.map { name in
            try NamedConnections.registry(environment: environment)
                .register(
                    name: name, provider: request.target == "codex" ? .codex : .anthropic,
                    reserved: (try? NamedConnections.reserved()) ?? [])
        }
        let store = NamedConnections.file(for: connection, environment: environment)
        switch request.target {
            case "claude": return try await claude(connection: connection, file: store, replace: request.replaceAccount)
            case "codex":
                return try await codex(
                    device: request.method == .device, connection: connection, file: store,
                    replace: request.replaceAccount)
            case "agy": return try await agy(file: store)
            case CopilotProtocol.name:
                let credentials = try await SignInRunner(clock: ContinuousClock())
                    .run(
                        CopilotDeviceSignIn(transport: transport), show: self.show)
                try store.saveCopilot(credentials)
                return "Signed in to Copilot (VS Code-style, experimental). Choose a model with /model."
            case "spettro": return try await spettro(file: store)
            default: return try await vibe(file: store)
        }
    }
}
