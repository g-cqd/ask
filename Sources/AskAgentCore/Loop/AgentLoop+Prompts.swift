// The messages the loop records in the person's place, recognised in sessions written by any version of ask.
extension AgentLoop {
    /// The reconnection messages earlier versions recorded. Sessions keep them, so a resumed one still shows a dropped connection as
    /// one, and never as a prompt the person wrote.
    public static let earlierReconnectionPrompts: Set<String> = [
        "[ask] The connection dropped while you were answering; what arrived is above. Continue exactly where it stopped, without "
            + "repeating it. If you were writing a tool call, it was dropped: issue it again."
    ]

    /// Whether `text` is a reconnection message, in the current wording or an earlier one.
    public static func isReconnectionPrompt(_ text: String) -> Bool {
        text == reconnectionPrompt || earlierReconnectionPrompts.contains(text)
    }

    /// Whether `text` is a message the loop recorded to carry a cut-off answer on, rather than one the person wrote.
    public static func isCarryOnPrompt(_ text: String) -> Bool {
        text == continuationPrompt || isReconnectionPrompt(text)
    }
}
