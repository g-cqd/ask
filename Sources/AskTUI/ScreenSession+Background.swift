extension ScreenSession {
    /// The command's block says it was sent once the call returns; only a miss is said here (roadmap 0173). `thread`: what that
    /// thread waits on, from its lane; main's when nil.
    static func sendCommandToBackground(
        _ conversation: any Conversation,
        thread: String?,
        _ sink: AsyncStream<ScreenEvent>.Continuation
    ) {
        guard !conversation.sendCommandToBackground(inThread: thread) else { return }
        let notice = ConversationUpdate.notice("Nothing is waited on in the foreground.", isError: false)
        sink.yield(.update(thread.map { .thread(id: $0, notice) } ?? notice))
    }
}
