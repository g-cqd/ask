internal import ArgumentParser
internal import AskAI
internal import Foundation

/// `ask login`: sign in to a provider. Claude by default.
struct Login: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Sign in to a provider.",
        discussion: "claude, codex: a subscription. spettro, mistral-vibe: a browser sign-in that issues an API key.")

    @Argument(help: "Which sign-in to run.") var provider: LoginTarget = .claude
    @Flag(help: "For codex: sign in with a code typed at a link, on a machine with no browser.") var device = false
    @Option(help: "Register a separate named codex or claude connection, without replacing the default account.")
    var name: String?
    @Flag(help: "Authorize replacing the remote account bound to this named connection.") var replaceAccount = false

    func run() async throws {
        let connection: ConnectionRecord?
        if let name {
            let kind: ConnectionKind
            switch provider {
                case .codex: kind = .codex
                case .claude: kind = .anthropic
                default: throw ValidationError("Named sign-ins currently support codex and claude.")
            }
            connection = try NamedConnections.registry()
                .register(name: name, provider: kind, reserved: NamedConnections.reserved())
        } else {
            guard !replaceAccount else { throw ValidationError("--replace-account requires --name.") }
            connection = nil
        }
        let file = NamedConnections.file(for: connection)
        switch provider {
            case .claude: await claudeLogin(file: file, connection: connection)
            case .codex:
                await codexLogin(device: device, file: file, connection: connection, replaceAccount: replaceAccount)
            case .spettro:
                let flow: SpettroSignIn
                do {
                    let base = ProcessInfo.processInfo.environment["SPETTRO_API_URL"] ?? SpettroSignIn.defaultBase
                    flow = try SpettroSignIn(transport: URLSessionTransport(), base: base)
                } catch { fail("ask: sign-in failed: \(error)", code: 77) }
                await browserLogin(flow, keyName: SpettroSignIn.provider, file: file)
            case .mistralVibe:
                await browserLogin(
                    VibeSignIn(transport: URLSessionTransport()), keyName: VibeSignIn.provider, file: file)
        }
    }

    private func claudeLogin(file: CredentialFile, connection: ConnectionRecord?) async {
        let pending = PendingSignIn.begin()
        print("Open this URL and sign in:\n\n  \(pending.url)\n\nThen paste the code it shows (code#state):")
        guard let pasted = readLine(strippingNewline: true) else { fail("ask: no code entered.", code: 66) }
        do {
            let credentials = try await ClaudeAuthClient(transport: URLSessionTransport())
                .complete(pending, pasted: pasted, now: Date().timeIntervalSince1970)
            if let connection {
                try NamedConnections.registry().saveClaude(credentials, for: connection, replaceAccount: replaceAccount)
            } else {
                try file.saveClaude(credentials)
            }
            print("Signed in\(credentials.accountEmail.map { " as \($0)" } ?? ""). Credentials: \(file.url.path)")
        } catch {
            fail("ask: sign-in failed: \(error)", code: 77)
        }
    }
}
