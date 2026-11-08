/// What a clicked link opens with, as the conversation answers from the person's openers (roadmap 0216, ADR-0148).
public enum LinkOpening: Sendable, Equatable {
    /// As before openers: the system's app, and a file that would run shown in the Finder.
    case system
    /// In this app, by name or bundle identifier.
    case app(String)
    /// This command, its placeholders filled, from rule `rule`.
    case command([String], rule: Int)
    /// Not opened, for this reason.
    case refused(String)
}
