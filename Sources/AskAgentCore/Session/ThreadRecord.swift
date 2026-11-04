/// A fact about a thread, kept in a session as a record of its own, outside the conversation (roadmap 0195, ADR-0144). Main's session
/// says where each thread started and where it merged, so a resume rebuilds the tree; a thread's own session says whose thread it is,
/// so `/resume` does not list it as a conversation.
public struct ThreadRecord: Sendable, Equatable {
    public enum Event: String, Sendable, Equatable {
        /// It was forked: `prompt`, `parent` (a thread, or main when nil), its session `file`, and `at`, main's leaf then.
        case started
        /// It merged into its parent: its `summary`, and `at`, main's leaf then.
        case merged
        /// In the thread's own session: whose thread it is (`file`, main's session) and its `id`.
        case identity
    }

    public var event: Event
    public var id: String
    public var parent: String?
    public var prompt: String?
    public var file: String?
    public var at: EntryID?
    public var summary: String?

    public init(_ event: Event, id: String) {
        self.event = event
        self.id = id
    }

    /// `id` was forked from `parent` (main when nil), working on `prompt` in the session at `file`, at the leaf `at` of where it came from.
    public static func started(_ id: String, parent: String?, prompt: String, file: String, at: EntryID?)
        -> ThreadRecord
    {
        var record = ThreadRecord(.started, id: id)
        record.parent = parent
        record.prompt = prompt
        record.file = file
        record.at = at
        return record
    }

    /// `id` merged with `summary`, at the leaf `at` of the conversation it merged into.
    public static func merged(_ id: String, summary: String, at: EntryID?) -> ThreadRecord {
        var record = ThreadRecord(.merged, id: id)
        record.summary = summary
        record.at = at
        return record
    }

    /// In thread `id`'s own session: the main session at `file` is whose it is.
    public static func identity(_ id: String, of file: String) -> ThreadRecord {
        var record = ThreadRecord(.identity, id: id)
        record.file = file
        return record
    }
}
