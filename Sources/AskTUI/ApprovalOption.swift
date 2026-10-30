/// One answer of an approval question as the section draws it (roadmap 0116): its words, the letter that checks it (its number does
/// too), and what choosing it means.
struct ApprovalOption: Sendable, Equatable {
    let label: String
    let letter: Character
    let choice: ApprovalChoice
    /// What the conversation's block says after the question once this was chosen.
    let said: String

    static let allowOnce = ApprovalOption(
        label: "Allow this time", letter: "y", choice: .once, said: "allowed this time")
    static let allowSession = ApprovalOption(
        label: "Allow for the session", letter: "a", choice: .session, said: "allowed for the session")
    static let deny = ApprovalOption(label: "Deny", letter: "n", choice: .deny, said: "denied")
    static let yes = ApprovalOption(label: "Yes", letter: "y", choice: .once, said: "yes")
    static let no = ApprovalOption(label: "No", letter: "n", choice: .deny, said: "no")

    /// The answers of a question of `kind`, in the order they are drawn.
    static func options(for kind: ApprovalKind) -> [ApprovalOption] {
        switch kind {
            case .grant, .destructive: [allowOnce, allowSession, deny]
            case .confirm: [yes, no]
        }
    }
}
