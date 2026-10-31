/// One thing a command's list offers: what it shows, a gloss beside it, and the arguments the command runs with when it is chosen.
public struct ChoiceRow: Sendable, Equatable {
    public let label: String
    public let detail: String
    /// What follows the command's name when this row is chosen: `codex gpt-6-sol`.
    public let arguments: String
    /// Whether this is what is in force now, which the list marks.
    public let isCurrent: Bool
    /// Whether choosing it only writes ``arguments`` in the draft, for the person to finish, instead of running the command: a row that
    /// still needs a name or an address.
    public let completes: Bool
    /// The text the typed arguments must start with for this row to be listed at all, case aside; nil for a row always listed. A model
    /// several accounts serve lists its accounts only once the model is chosen (roadmap 0092).
    public let revealedBy: String?

    /// A row.
    public init(
        label: String, detail: String = "", arguments: String, isCurrent: Bool = false, completes: Bool = false,
        revealedBy: String? = nil
    ) {
        self.label = label
        self.detail = detail
        self.arguments = arguments
        self.isCurrent = isCurrent
        self.completes = completes
        self.revealedBy = revealedBy?.lowercased()
    }
}
