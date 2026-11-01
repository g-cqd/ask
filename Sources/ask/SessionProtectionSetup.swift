internal import AskAgentCore

/// Before the screen opens (ADR-0138): the first-start question when nothing has been decided, the question for this conversation when
/// `sessionEncryption` is `"ask"`, and the keys unlocked or set up when sessions are to be encrypted.
enum SessionProtectionSetup {
    enum Refusal: Error, CustomStringConvertible {
        case cannotUnlock

        var description: String {
            "sessions are to be encrypted (sessionEncryption), and their keys could not be opened here: run ask in a terminal to type the "
                + "password, or set sessionPassword to \"remember\""
        }
    }

    static func decide(_ configuration: Configuration) async throws -> SessionProtection {
        let vault = SessionKeyAccess.vault
        let policy = SessionEncryptionPolicy(
            setting: configuration.sessionEncryption.value,
            password: configuration.sessionPassword.value,
            choice: vault.choice()
        )
        let compressed = configuration.sessionCompression.value
        let plain = SessionProtection(format: SessionFormat(compressed: compressed, encrypted: false), keyring: nil)
        let terminal = CommandLineInteraction()
        var encrypt = policy.mode == .on
        var remember = policy.remember
        if policy.needsFirstStartQuestion {
            guard SessionKeyAccess.canAsk else { return plain }
            encrypt = await yes(
                terminal,
                "Encrypt your ask sessions? They then open only with your password or a recovery code. [y/N]",
                default: false
            )
            if encrypt {
                remember = await yes(terminal, "Keep the key in your keychain, so ask does not ask at start? [Y/n]")
            }
            try? vault.record(SessionEncryptionChoice(encrypt: encrypt, remember: remember))
            terminal.say("Change this any time with sessionEncryption and sessionPassword in your config.")
        } else if policy.mode == .ask {
            guard SessionKeyAccess.canAsk else { throw Refusal.cannotUnlock }
            encrypt = await yes(terminal, "Encrypt this conversation? [Y/n]")
        }
        guard encrypt else { return plain }
        let keyring =
            vault.hasKeys
            ? await SessionKeyAccess.unlock(remember: remember) : await SessionKeyAccess.setUp(remember: remember)
        guard let keyring else { throw Refusal.cannotUnlock }
        return SessionProtection(format: SessionFormat(compressed: compressed, encrypted: true), keyring: keyring)
    }

    private static func yes(_ terminal: CommandLineInteraction, _ question: String, default answer: Bool = true) async
        -> Bool
    {
        guard let reply = await terminal.ask(question, secret: false)?.lowercased() else { return answer }
        if reply.hasPrefix("y") { return true }
        if reply.hasPrefix("n") { return false }
        return answer
    }
}
