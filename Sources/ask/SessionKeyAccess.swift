internal import AskAI
internal import AskAgentCore
internal import Darwin
internal import Synchronization

/// The keys of encrypted sessions for this process (ADR-0138, roadmap 0182): decided once before the screen opens, then used by every
/// session the run makes, resumes or forks. Unlocked from the keychain when remembered, else with the password asked on the terminal,
/// the recovery code standing in for a forgotten one.
enum SessionKeyAccess {
    private static let held = Mutex<SessionKeyring?>(nil)
    private static let decided = Mutex(SessionProtection.plain)

    static var vault: SessionVault {
        SessionVault(stateRoot: SessionDirectory.stateRoot(environment: LaunchEnvironment.values))
    }
    /// How new sessions are kept this run.
    static var protection: SessionProtection { decided.withLock { $0 } }
    /// The keyring, once unlocked.
    static var keyring: SessionKeyring? { held.withLock { $0 } }

    static func decide(_ protection: SessionProtection) {
        decided.withLock { $0 = protection }
        if let keyring = protection.keyring { held.withLock { $0 = keyring } }
    }

    static var canAsk: Bool { isatty(STDIN_FILENO) == 1 && isatty(STDOUT_FILENO) == 1 }

    private static func keychain() -> (any SecretStore)? { try? KeychainSecretStore() }

    /// The keyring: held already, remembered in the keychain, or opened with the password `asker` gets (three tries), then with the
    /// recovery code. Nil when there are no keys, nothing could open them, or there is no one to ask.
    static func unlock(remember: Bool, asker: (any SetupInteraction)?) async -> SessionKeyring? {
        if let keyring { return keyring }
        let vault = vault
        guard vault.hasKeys else { return nil }
        if let store = keychain(), let remembered = vault.remembered(in: store) {
            held.withLock { $0 = remembered }
            return remembered
        }
        guard let terminal = asker else { return nil }
        for attempt in 1 ... 3 {
            guard let password = await terminal.ask("Password for your encrypted ask sessions:", secret: true),
                !password.isEmpty
            else { break }
            if let opened = try? vault.unlock(password: password) {
                return keep(opened, remember: remember)
            }
            terminal.say(attempt < 3 ? "That is not the password." : "That is not the password either.")
        }
        guard
            let code = await terminal.ask("Your recovery code (empty to go on without these sessions):", secret: true),
            !code.isEmpty,
            let opened = try? vault.unlock(recoveryCode: code)
        else { return nil }
        terminal.say("Opened with the recovery code. Set a new password with `ask keys password`.")
        return keep(opened, remember: remember)
    }

    /// New keys: a password typed twice, and the recovery code shown once.
    static func setUp(remember: Bool, asker: (any SetupInteraction)?) async -> SessionKeyring? {
        guard let terminal = asker else { return nil }
        terminal.say(
            "Choose a password for your ask sessions. Without it, or the recovery code ask shows next, they cannot be read."
        )
        var password: String?
        for _ in 1 ... 3 where password == nil {
            guard let first = await terminal.ask("Password:", secret: true), first.count >= 8 else {
                terminal.say("At least 8 characters.")
                continue
            }
            guard await terminal.ask("Again:", secret: true) == first else {
                terminal.say("The two did not match.")
                continue
            }
            password = first
        }
        guard let password, let made = try? vault.create(password: password) else { return nil }
        await terminal.showOnce(
            """

            Your recovery code, shown this once. Keep it somewhere safe: it opens your sessions if you forget the password.

                \(made.recoveryCode)

            Press Return when it is kept.
            """
        )
        return keep(made.keyring, remember: remember)
    }

    private static func keep(_ keyring: SessionKeyring, remember: Bool) -> SessionKeyring {
        held.withLock { $0 = keyring }
        if remember, let store = keychain() { try? vault.remember(keyring, in: store) }
        return keyring
    }
}
