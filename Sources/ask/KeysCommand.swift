internal import ArgumentParser
internal import AskAI
internal import AskAgentCore
internal import AskSession
internal import Foundation

/// `ask keys`: the keys of encrypted sessions (ADR-0138, roadmap 0182). `password` sets a new password, opening the keys with the old one
/// or the recovery code; `forget` removes the key kept in the keychain, so the password is asked at the next start.
struct KeysCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "keys",
        abstract: "The keys of encrypted sessions: a new password, or the keychain's copy forgotten.",
        discussion:
            "ask keys password: opens the keys with the password or the recovery code, then asks for a new password.\n"
            + "ask keys forget: removes the key from the keychain; the password is asked at the next start."
    )

    @Argument(help: "password or forget.") var action: String

    func run() async throws {
        let vault = SessionKeyAccess.vault
        guard vault.hasKeys else { fail("ask: no encrypted sessions are set up (sessionEncryption)", code: 66) }
        switch action {
            case "forget":
                do { try vault.forget(in: try KeychainSecretStore()) } catch { fail("ask: \(error)", code: 77) }
                print("The keychain no longer holds the key; ask asks for the password at the next start.")
            case "password":
                guard let keyring = await SessionKeyAccess.unlock(remember: false, asker: TerminalSetupInteraction())
                else {
                    fail("ask: the keys could not be opened", code: 77)
                }
                let terminal = CommandLineInteraction()
                guard let password = await terminal.ask("New password:", secret: true), password.count >= 8 else {
                    fail("ask: a password has at least 8 characters", code: 64)
                }
                guard await terminal.ask("Again:", secret: true) == password else {
                    fail("ask: the two did not match", code: 64)
                }
                do { try vault.changePassword(keyring, to: password) } catch { fail("ask: \(error)", code: 74) }
                print("The password is changed. Every session opens with it; the recovery code still works.")
            default:
                throw ValidationError("ask keys takes password or forget.")
        }
    }
}
