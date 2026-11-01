internal import AskAgentCore
internal import AskTUI
internal import Synchronization

/// The keys' questions inside the screen (idea i1, ADR-0138).
extension AgentConversation {
    /// The decision left for the screen, asked as soon as it is up. When the person wants encryption and the keys cannot be opened,
    /// nothing is written in this run: prompts are refused, and the screen says why.
    func settleProtection(update: @escaping @Sendable (ConversationUpdate) -> Void) async {
        guard SessionKeyAccess.isPending else { return }
        let configuration = current.withLock { $0.settings.configuration }
        let asker = ScreenSetupInteraction(conversation: self, update: update)
        do {
            let decided = try await SessionProtectionSetup.decide(configuration, asker: asker, deferring: false)
            let plain = SessionFormat(compressed: configuration.sessionCompression.value, encrypted: false)
            SessionKeyAccess.settle(decided ?? SessionProtection(format: plain, keyring: nil))
        } catch {
            SessionKeyAccess.refuse()
            update(.notice("Nothing will be saved in this run: \(error).", isError: true))
        }
    }

    /// The keys for `/encrypt on`: open already, or opened or set up here.
    func keysForEncrypt(update: @escaping @Sendable (ConversationUpdate) -> Void) async -> SessionKeyring? {
        if let keyring = SessionKeyAccess.keyring { return keyring }
        let asker = ScreenSetupInteraction(conversation: self, update: update)
        let remember = SessionKeyAccess.vault.choice()?.remember ?? true
        return SessionKeyAccess.vault.hasKeys
            ? await SessionKeyAccess.unlock(remember: remember, asker: asker)
            : await SessionKeyAccess.setUp(remember: remember, asker: asker)
    }
}
