internal import AskAI
internal import AskAgentCore
internal import AskMCP
internal import AskTUI
internal import AskTools
internal import Foundation

#if canImport(AppKit)
    internal import AppKit
#endif

/// Signing in to a remote MCP server that needs it (roadmap 0067): asked on the screen when the server refuses (the owner's choice,
/// 2026-11-02), or with `/mcp login <server>`.
extension AgentConversation {
    /// `/mcp`, `/mcp login <server>`.
    func mcpCommand(_ arguments: String, update: @escaping @Sendable (ConversationUpdate) -> Void) {
        let words = arguments.split(separator: " ").map(String.init)
        switch words.first {
            case nil: update(.notice(MCPHub.report(mcp.status).joined(separator: "\n"), isError: false))
            case "login" where words.count == 2: Task { await self.signIn(toMCP: words[1], update: update) }
            default:
                update(.notice("Usage: /mcp lists the servers; /mcp login <server> signs in to one.", isError: true))
        }
    }

    /// Asks the person, for each server that refuses for want of a sign-in, whether to sign in now; yes opens the browser.
    func askToSignIn(update: @escaping @Sendable (ConversationUpdate) -> Void) async {
        for await name in mcp.signInNeeds {
            // The refusal comes while a turn connects its servers: asked once it has ended, as the end of a turn clears its questions.
            await untilTurnEnds()
            let question = PersonQuestion(
                question: "The MCP server \(name) needs you to sign in. Open the browser to sign in now?",
                header: "Sign in",
                choices: [
                    .init(
                        label: "Sign in",
                        description: "Opens your browser; \(name) connects once you approve there."
                    ),
                    .init(label: "Not now", description: "It stays off until /mcp login \(name).")
                ],
                note: .none
            )
            guard let answer = await askPerson([question], via: update)?.first, answer.chosen == [0] else {
                update(.notice("\(name) stays off until /mcp login \(name).", isError: false))
                continue
            }
            await signIn(toMCP: name, update: update)
        }
    }

    /// Signs in to `name` in the browser and connects it, saying how it went.
    func signIn(toMCP name: String, update: @escaping @Sendable (ConversationUpdate) -> Void) async {
        do {
            try await mcp.signIn(
                name,
                file: CredentialFile.standard(environment: LaunchEnvironment.values),
                http: URLSessionTransport()
            ) { url in
                let opened = Self.openInBrowser(url)
                let notice =
                    opened
                    ? "Approve ask in your browser to sign in to \(name). If nothing opened: \(url.absoluteString)"
                    : "Open this address in a browser to sign in to \(name): \(url.absoluteString)"
                update(.notice(notice, isError: false))
            }
            update(.notice("Signed in to \(name): it connects now.", isError: false))
        } catch {
            update(.notice("Signing in to \(name) failed: \(error.reason)", isError: true))
        }
    }

    /// Opens `url` in the default browser through `NSWorkspace`, the system's way. Over SSH, or with `ASK_NO_BROWSER` set, nothing
    /// opens and the address is only shown: a browser on this machine is not the person's, or a probe follows the address itself.
    /// - Returns: whether a browser was asked to open it.
    private static func openInBrowser(_ url: URL) -> Bool {
        let environment = LaunchEnvironment.values
        guard environment["ASK_NO_BROWSER"] == nil, environment["SSH_TTY"] == nil, environment["SSH_CONNECTION"] == nil
        else {
            return false
        }
        #if canImport(AppKit)
            return NSWorkspace.shared.open(url)
        #else
            return false
        #endif
    }
}
