/// A thread about to start (roadmap 0195, the `thread.start` hook point): its name, the thread it is under (nil for main), and its task.
public struct ThreadStart: Sendable, Equatable {
    public let name: String
    public let parent: String?
    public let prompt: String

    public init(name: String, parent: String?, prompt: String) {
        self.name = name
        self.parent = parent
        self.prompt = prompt
    }
}
