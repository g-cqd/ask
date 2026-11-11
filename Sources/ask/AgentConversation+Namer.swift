internal import AskAI
internal import AskAgentCore
internal import Synchronization

/// Which model names threads and the conversation, and so the tab (`threads.names`, roadmap 0195; note n66, the owner 2026-11-11):
/// Apple's on-device model by default, a provider's with "model", none with "numbered".
extension AgentConversation {
    /// Whether `threads.names` asks a model for names at all.
    var namingEnabled: Bool {
        current.withLock { $0.settings.configuration.threads.value.naming } != .numbered
    }

    /// A name for `text` by the model `threads.names` chooses, when it answers in time; nil with "numbered".
    func chosenName(for text: String) async -> String? {
        switch current.withLock({ $0.settings.configuration.threads.value.naming }) {
            case .numbered: return nil
            case .model:
                guard let model = await namingModel() else { return await ThreadNamer.name(for: text) }
                let provider = makeProvider(model, transport: URLSessionTransport())
                return await ThreadNamer.name(for: text, by: provider, model: model.model, within: .seconds(15))
            case .onDevice: return await ThreadNamer.name(for: text)
        }
    }

    /// The model `threads.names` "model" asks (note n20): `threads.namesModel` read as `/model` reads its word, else the conversation's
    /// own; nil when the one named does not resolve.
    private func namingModel() async -> ResolvedModel? {
        let settings = current.withLock { $0.settings }
        guard let word = settings.configuration.threads.value.namingModel else { return settings.model }
        return try? await self.settings(forModel: word).model
    }
}
