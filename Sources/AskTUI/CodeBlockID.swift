/// One fenced code block in the transcript: the assistant item it is in, and its place among that item's fences. Fences are only
/// appended while a message streams, so the ordinal of a block does not change.
struct CodeBlockID: Hashable, Sendable {
    var item: Int
    var fence: Int
}
