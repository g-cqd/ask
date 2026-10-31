internal import ArgumentParser
internal import AskAI
internal import Foundation

/// `ask login`: sign in to a provider, with its account or with an API key. Claude by default.
struct Login: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Sign in to a provider, with its account or an API key.",
        discussion: """
            claude, codex: a subscription in a browser; add --api-key to use an API key instead (codex's is OpenAI's, stored as `openai`).
            agy: a Google account for Antigravity. spettro, mistral-vibe: a browser sign-in that issues an API key.
            Any provider with a key preset (groq, openrouter, …): its API key. custom NAME URL: any OpenAI-compatible server.
            """)

    @Argument(help: "Which sign-in to run: a provider, or custom NAME URL.") var words: [String] = []
    @Flag(help: "Sign in with an API key instead of an account.") var apiKey = false
    @Flag(help: "For codex: sign in with a code typed at a link, on a machine with no browser.") var device = false
    @Option(
        help:
            "Sign in to codex or claude as a named connection. Without it, another account than the default's is added as one."
    )
    var name: String?
    @Flag(help: "Replace the account of the named connection, or of the default without --name.") var replaceAccount =
        false

    func run() async throws {
        var all = words
        if all.isEmpty { all = ["claude"] }
        if apiKey { all.append("api-key") }
        if device { all.append("device") }
        if let name { all += ["--name", name] }
        if replaceAccount { all.append("--replace-account") }
        let request: LoginRequest
        do { request = try LoginRequest(words: all) } catch { throw ValidationError("\(error)") }
        do {
            print(try await AccountLogin(interaction: CommandLineInteraction()).run(request))
        } catch { fail("ask: sign-in failed: \(error)", code: 77) }
    }
}
