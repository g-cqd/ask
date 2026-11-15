package import AskTUI

/// A session an ACP client asked for (`session/new`): the conversation that serves it, and the id the client names it by.
package struct ACPSession: Sendable {
    /// Makes the session for a client's working directory, an absolute path. What it throws is said to the client.
    package typealias Source = @Sendable (_ cwd: String) async throws -> ACPSession

    package let id: String
    /// The session's folder, absolute: what a relative path in a tool call is relative to.
    package let folder: String
    package let conversation: any Conversation

    package init(id: String, folder: String, conversation: any Conversation) {
        self.id = id
        self.folder = folder
        self.conversation = conversation
    }
}
