/// The one runner whose output the screen streams: started when its lane asks for it, stopped when another lane, or none, is shown.
struct RunnerOutputWatch {
    private var task: Task<Void, Never>?
    private var id: String?

    /// Streams runner `id`'s output into `sink`, in place of any runner watched before.
    mutating func watch(_ id: String, in conversation: any Conversation, sink: AsyncStream<ScreenEvent>.Continuation) {
        task?.cancel()
        self.id = id
        task = conversation.watchRunnerOutput(id) { sink.yield(.update(.runnerOutput(id: id, text: $0))) }
    }

    /// Stops watching once the lane shown is no longer the watched runner's.
    mutating func sync(lane: String?) {
        guard id != lane else { return }
        stop()
    }

    mutating func stop() {
        task?.cancel()
        task = nil
        id = nil
    }
}
