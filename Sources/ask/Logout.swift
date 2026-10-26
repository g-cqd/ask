internal import ArgumentParser
internal import AskAI
internal import Foundation

/// `ask logout`: forget stored credentials, one account's or all.
struct Logout: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Forget stored credentials.")

    @Argument(
        help:
            "Forget only this sign-in: claude, codex, agy, a stored key's provider, or a named connection. Default: all."
    )
    var provider: String?

    func run() throws {
        do { print(try AccountLogout(environment: LaunchEnvironment.values).run(provider)) } catch {
            fail("ask: \(error)", code: 78)
        }
    }
}
