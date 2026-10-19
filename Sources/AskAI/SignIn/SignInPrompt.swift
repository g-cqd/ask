public import Foundation

/// What the user is shown to sign in: the link to open, and what to do there, such as a code to type.
public struct SignInPrompt: Sendable, Equatable {
    public let url: URL
    public let instructions: String?

    /// A prompt for `url`, with optional `instructions`.
    public init(url: URL, instructions: String? = nil) {
        self.url = url
        self.instructions = instructions
    }
}
