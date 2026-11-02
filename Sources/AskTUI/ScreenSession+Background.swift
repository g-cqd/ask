extension ScreenSession {
    /// The command's block says it was sent once the call returns; only a miss is said here (roadmap 0173).
    static func sendCommandToBackground(_ conversation: any Conversation, _ sink: AsyncStream<ScreenEvent>.Continuation)
    {
        guard !conversation.sendCommandToBackground() else { return }
        sink.yield(.update(.notice("No command is running in the foreground.", isError: false)))
    }
}
