/// A thread about to merge into its parent (the `thread.merge` and `thread.merged` hook points).
public struct ThreadMerge: Sendable, Equatable {
    public let name: String
    public let parent: String?

    public init(name: String, parent: String?) {
        self.name = name
        self.parent = parent
    }
}
