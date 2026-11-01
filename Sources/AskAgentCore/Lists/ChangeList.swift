/// A list kept as its changes beside a session (ADR-0140): the task list, the ideas. Replaying the changes in order rebuilds it, and a
/// change it refuses leaves it as it was.
public protocol ChangeList: Sendable, Equatable {
    associatedtype Change: Codable, Sendable

    /// The file beside a session: `<session>.<suffix>`.
    static var suffix: String { get }
    /// The file beside the workspace's sessions, for a list they share.
    static var workspaceName: String { get }

    init()
    mutating func apply(_ change: Change) throws
}
