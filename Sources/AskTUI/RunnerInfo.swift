/// A node in the runner tree. Jobs supply the nodes today; a parent need not precede its children in an update.
public struct RunnerInfo: Sendable, Equatable {
    /// Stable across updates, independent of the display name.
    public var id: String
    /// Nil at the top; a missing parent is shown as a root rather than losing the node.
    public var parentID: String?
    /// What this runner is. No agent is created by this UI model.
    public var kind: Kind
    /// Its activity, supplied by the owner of the runner.
    public var state: State

    public enum Kind: Sendable, Equatable { case job, agent }
    public enum State: String, Sendable, Equatable {
        case running
        case waitingForApproval = "waiting for approval"
        case done, failed, stopped

        public var isActive: Bool { self == .running || self == .waitingForApproval }
    }

    /// How the model and the user name it, such as `job-3`.
    public var name: String
    /// What it is doing, such as the command line. Line breaks are shown as spaces.
    public var detail: String

    /// A runner. An omitted id is its name, for jobs whose name is already stable.
    public init(
        name: String, detail: String, id: String? = nil, parentID: String? = nil, kind: Kind = .job,
        state: State = .running
    ) {
        self.id = id ?? name
        self.parentID = parentID
        self.kind = kind
        self.state = state
        self.name = name
        self.detail = detail
    }
}
