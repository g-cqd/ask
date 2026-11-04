extension ScreenSession {
    /// What the person did in a thread's lane (roadmap 0194): a message for the thread, or `/thread` from it.
    static func performThread(
        _ effect: ScreenController.Effect,
        _ conversation: any Conversation,
        _ sink: AsyncStream<ScreenEvent>.Continuation
    ) {
        switch effect {
            case .sendToThread(let id, let text):
                conversation.sendToThread(id, text: text) { sink.yield(.update($0)) }
            case .startThread(let parent, let text):
                Task { await conversation.startThread(text, from: parent) { sink.yield(.update($0)) } }
            default: break
        }
    }
}
