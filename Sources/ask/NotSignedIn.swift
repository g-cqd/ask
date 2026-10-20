internal import AemiJSON
internal import AskAI
internal import AskAgentCore
internal import AskTools
internal import Foundation

/// Signed out, said so a person can act on it.
struct NotSignedIn: Error, CustomStringConvertible {
    var description: String {
        "not signed in. Run `ask login`, or set ANTHROPIC_API_KEY (ANTHROPIC_AUTH_TOKEN and ANTHROPIC_OAUTH_TOKEN also work)."
    }
}
