internal import AskAgentCore

/// How this run's sessions are kept (ADR-0138): the first-start question when nothing has been decided, the question for this
/// conversation when `sessionEncryption` is `"ask"`, and the keys unlocked or set up when sessions are to be encrypted. Asked through
/// `asker`: the terminal before a screen, or the screen once it is up (idea i1).
enum SessionProtectionSetup {
    enum Refusal: Error, CustomStringConvertible {
        case cannotUnlock

        var description: String {
            "sessions are to be encrypted (sessionEncryption), and their keys could not be opened: ask again with the password, or set "
                + "sessionPassword to \"remember\""
        }
    }

    /// The decision, or nil when it needs a person, there is no `asker`, and `deferring` leaves it for the screen. Without an asker
    /// and not deferring: no first-start question (sessions stay plain, asked next time), and keys that need a password refuse.
    static func decide(
        _ configuration: Configuration,
        asker: (any SetupInteraction)?,
        deferring: Bool
    ) async throws -> SessionProtection? {
        let vault = SessionKeyAccess.vault
        let policy = SessionEncryptionPolicy(
            setting: configuration.sessionEncryption.value,
            password: configuration.sessionPassword.value,
            choice: vault.choice()
        )
        let compressed = configuration.sessionCompression.value
        let plain = SessionProtection(format: SessionFormat(compressed: compressed, encrypted: false), keyring: nil)
        var encrypt = policy.mode == .on
        var remember = policy.remember
        if policy.needsFirstStartQuestion {
            guard let asker else { return deferring ? nil : plain }
            // Closed without an answer: plain for this run, and asked again at the next start.
            guard let answer = await firstStart(asker) else { return plain }
            (encrypt, remember) = answer
            do {
                try vault.record(SessionEncryptionChoice(encrypt: encrypt, remember: remember))
                asker.say("Change this any time with sessionEncryption and sessionPassword in your config.")
            } catch {
                asker.say("Your choice could not be saved (\(error)); ask asks again at the next start.")
            }
        } else if policy.mode == .ask {
            guard let asker else {
                if deferring { return nil }
                throw Refusal.cannotUnlock
            }
            encrypt =
                await asker.choose("Encrypt this conversation?", header: "Encryption", ["Yes", "No"], fallback: 0) != 1
        }
        guard encrypt else { return plain }
        let keyring =
            vault.hasKeys
            ? await SessionKeyAccess.unlock(remember: remember, asker: asker)
            : await SessionKeyAccess.setUp(remember: remember, asker: asker)
        guard let keyring else {
            if asker == nil, deferring { return nil }
            throw Refusal.cannotUnlock
        }
        return SessionProtection(format: SessionFormat(compressed: compressed, encrypted: true), keyring: keyring)
    }

    /// How this run's sessions are kept, at launch. A new interactive conversation decides here only what needs nobody (the setting, the
    /// keychain) and asks the rest once its screen is up (idea i1); a prompt run or a resumed session asks on the terminal.
    static func decideAtLaunch(_ configuration: Configuration, inScreen wanted: Bool) async {
        let inScreen = wanted && SessionKeyAccess.canAsk
        let asker: (any SetupInteraction)? = SessionKeyAccess.canAsk && !inScreen ? TerminalSetupInteraction() : nil
        do {
            if let protection = try await decide(configuration, asker: asker, deferring: inScreen) {
                SessionKeyAccess.decide(protection)
            } else {
                SessionKeyAccess.leavePending()
            }
        } catch {
            fail("ask: \(error)", code: 77)
        }
    }

    /// Whether to encrypt, and whether to keep the key in the keychain; nil when the person closed the question.
    private static func firstStart(_ asker: any SetupInteraction) async -> (encrypt: Bool, remember: Bool)? {
        guard
            let encrypt = await asker.choose(
                "Encrypt your ask sessions? They then open only with your password or a recovery code.",
                header: "Encryption",
                ["Yes", "No"],
                fallback: 1
            )
        else { return nil }
        guard encrypt == 0 else { return (false, true) }
        let remember = await asker.choose(
            "Keep the key in your keychain, so ask does not ask at start?",
            header: "Keychain",
            ["Yes", "No"],
            fallback: 0
        )
        guard let remember else { return nil }
        return (true, remember == 0)
    }
}
