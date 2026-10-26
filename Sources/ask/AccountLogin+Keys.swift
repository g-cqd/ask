internal import AskAI
internal import Foundation

/// The sign-ins that end in an API key: typed by the person, or issued to a browser sign-in.
extension AccountLogin {
    /// Asks for a key and stores it under the name the provider is reached by. `custom` first adds the endpoint to `providers.json`.
    func signInWithKey(_ request: LoginRequest) async throws -> String {
        guard var provider = request.keyProvider else { throw Failure("\(request.target) has no key to enter.") }
        if request.target == "custom" {
            guard let name = request.endpointName, let address = request.endpointURL else {
                throw Failure(
                    "usage: login custom NAME URL (the URL ends where /models and /chat/completions begin, such as https://host/v1)"
                )
            }
            do {
                provider = try ProviderFile.addEndpoint(
                    name: name, baseURL: address, at: askConfigDirectory(environment: environment) + "/providers.json")
            } catch { throw Failure("\(error)") }
        }
        let label = request.target == "codex" ? "OpenAI" : (request.target == "claude" ? "Anthropic" : provider)
        guard
            let typed = await interaction.ask(
                "Paste the \(label) API key (it is not shown or kept anywhere else):", secret: true)
        else { throw Failure.nothingEntered }
        // A custom endpoint may be a local server that wants none: an empty answer stores nothing and keeps the endpoint.
        if request.target == "custom", typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Added \(provider) with no key. Choose its model with /model \(provider) MODEL."
        }
        guard let key = APIKey.clean(typed) else {
            throw Failure("that is not an API key: it is empty, too long, or has a space or a control character.")
        }
        try file.saveAPIKey(key, for: provider, now: Date().timeIntervalSince1970)
        return "API key stored for \(provider). Choose a model with /model \(provider) MODEL."
    }

    func spettro(file: CredentialFile) async throws -> String {
        let base = environment["SPETTRO_API_URL"] ?? SpettroSignIn.defaultBase
        let flow = try SpettroSignIn(transport: transport, base: base)
        return try await browserKey(flow, keyName: SpettroSignIn.provider, file: file)
    }

    func vibe(file: CredentialFile) async throws -> String {
        try await browserKey(VibeSignIn(transport: transport), keyName: VibeSignIn.provider, file: file)
    }

    /// Signs in through a browser and stores the key it issues.
    private func browserKey<Flow: KeySignIn>(_ flow: Flow, keyName: String, file: CredentialFile) async throws -> String
    {
        let key = try await SignInRunner(clock: ContinuousClock())
            .run(flow, show: self.show)
        try file.saveKey(key, for: keyName)
        return "Signed in. Key stored for \(keyName)."
    }
}
