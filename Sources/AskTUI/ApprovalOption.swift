/// One answer of an approval question as the section draws it (roadmap 0116): its words, the letter that checks it (its number does
/// too), and what choosing it means. Another driver of the conversation offers the same answers in the same words (ADR-0154), so
/// the words, which say how far an answer reaches, and the choice are public.
public struct ApprovalOption: Sendable, Equatable {
    public let label: String
    let letter: Character
    public let choice: ApprovalChoice
    /// What the conversation's block says after the question once this was chosen.
    let said: String

    static let allowOnce = ApprovalOption(
        // @dl:accept -- the answers are a table: each a label, a letter, a choice and what is said; the words are the data
        label: "Allow this time",
        letter: "y",
        choice: .once,
        said: "allowed this time"
    )
    static let allowSession = ApprovalOption(
        label: "Allow for the session",
        letter: "a",
        choice: .session,
        said: "allowed for the session"
    )
    /// Kept until revoked (ADR-0148), unlike a session's grant.
    static let allowAlways = ApprovalOption(
        // @dl:accept -- the answers are a table: each a label, a letter, a choice and what is said; the words are the data
        label: "Always allow this command",
        letter: "a",
        choice: .session,
        said: "always allowed"
    )
    static let deny = ApprovalOption(label: "Deny", letter: "n", choice: .deny, said: "denied")
    static let yes = ApprovalOption(label: "Yes", letter: "y", choice: .once, said: "yes")
    static let no = ApprovalOption(label: "No", letter: "n", choice: .deny, said: "no")

    /// The answers of a question of `kind`, in the order they are drawn.
    public static func options(for kind: ApprovalKind) -> [ApprovalOption] {
        switch kind {
            case .grant, .destructive: return [allowOnce, allowSession, deny]
            case .confirm: return [yes, no]
            case .opener(let remembers): return remembers ? [allowOnce, allowAlways, deny] : [allowOnce, deny]
            case .command(let phrases, let programs):
                guard !phrases.isEmpty else { return [allowOnce, deny] }
                let named = quoted(phrases)
                let session = ApprovalOption(
                    label: "Allow \(named) for the session",
                    letter: "a",
                    choice: .session,
                    said: "allowed \(named) for the session"
                )
                guard programs != phrases else { return [allowOnce, session, deny] }
                let program = ApprovalOption(
                    label: "Allow \(quoted(programs)) for the session",
                    letter: "p",
                    choice: .program,
                    said: "allowed \(quoted(programs)) for the session"
                )
                return [allowOnce, session, program, deny]
        }
    }

    /// `git status`, `swift build`, each in backquotes.
    private static func quoted(_ words: [String]) -> String {
        words.map { "`\($0)`" }.joined(separator: ", ")
    }
}
