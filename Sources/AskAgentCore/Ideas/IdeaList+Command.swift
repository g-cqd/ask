/// `/ideas` (roadmap 0180): an idea's id, alone to start editing it, or with the words that replace it.
extension IdeaList {
    public struct Edit: Equatable, Sendable {
        public let id: Int
        /// The new text, verbatim after the id and one space; nil to start editing.
        public let text: String?
    }

    /// What `/ideas ARGUMENTS` edits, when the arguments start with an id such as `i3`.
    public static func editing(_ arguments: String) -> Edit? {
        let trimmed = arguments.drop(while: \.isWhitespace)
        let head = trimmed.prefix { !$0.isWhitespace }
        guard head.first == "i", let id = Int(head.dropFirst()) else { return nil }
        let rest = trimmed.dropFirst(head.count)
        return Edit(id: id, text: rest.isEmpty ? nil : String(rest.dropFirst()))
    }

    /// The draft that edits idea `id`: the command, its id, and its text to change.
    public func draft(editing id: Int) -> String? { idea(id).map { "/ideas \($0.name) \($0.text)" } }
}
