/// An approval question waiting for its answer (roadmap 0116): which answer the cursor is on, and which is checked.
public struct PendingApproval: Sendable, Equatable {
    /// Which question it is, so the answer reaches the call that asked.
    public let id: Int
    public let question: String
    public let kind: ApprovalKind
    /// The call's whole command, shown under the question, folded to one row until unfolded (roadmap 0157); nil shows none.
    public let detail: String?
    /// Whether the command is unfolded.
    public internal(set) var showsWholeDetail = false
    /// The row the arrows are on.
    public internal(set) var cursor: Int
    /// The row checked: what Enter confirms.
    public internal(set) var checked: Int

    public init(id: Int, question: String, kind: ApprovalKind = .grant, detail: String? = nil) {
        self.id = id
        self.question = question
        self.kind = kind
        self.detail = detail.flatMap { $0.contains { !$0.isWhitespace } ? $0 : nil }
        let start =
            switch kind {
                case .grant, .command: 0
                case .destructive, .confirm: ApprovalOption.options(for: kind).count - 1
            }
        cursor = start
        checked = start
    }

    /// The answers, in the order they are drawn.
    var options: [ApprovalOption] { ApprovalOption.options(for: kind) }

    /// The shortcuts, as the status line names them in a job lane: `y · a · n, then Enter`.
    var shortcutHint: String { options.map { String($0.letter) }.joined(separator: " · ") + ", then Enter" }
}
