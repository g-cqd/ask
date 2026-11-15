package import AskTUI

/// A session an ACP client asked for (`session/new`): the conversation that serves it, and the id the client names it by.
package struct ACPSession: Sendable {
    /// Makes the session for a client's working directory, an absolute path. What it throws is said to the client.
    package typealias Source = @Sendable (_ cwd: String) async throws -> ACPSession

    /// Opens the saved session `id` of a client's working directory, to be continued; nil when there is no such session. What it
    /// throws is said to the client.
    package typealias Loader = @Sendable (_ id: String, _ cwd: String) async throws -> Loaded?

    /// A saved session opened again: the session, and what it holds as the conversation says it, oldest first.
    package struct Loaded: Sendable {
        package let session: ACPSession
        package let history: [ConversationUpdate]

        package init(session: ACPSession, history: [ConversationUpdate]) {
            self.session = session
            self.history = history
        }
    }

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
