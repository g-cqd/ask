/// What was sent, for Up and Down to browse (roadmap 0111): prompts and `/` commands in order, the newest last. Browsing keeps the draft
/// that was being typed and gives it back at the newest end. Once a recalled entry is edited, there is no going to a newer one: the
/// edited text is the draft from then on.
struct PromptHistory: Sendable {
    /// The most entries kept; the oldest go first.
    static let limit = 1_000

    private(set) var entries: [String] = []
    /// The entry shown now, while browsing.
    private var index: Int?
    /// What the editor held before browsing began, or the edited entry since.
    private var draft = ""
    /// What the editor was given last, to tell an edit from a recalled entry left as it was.
    private var recalled = ""

    /// Whether the editor shows a recalled entry as it was: the picker stays closed then, so Up and Down keep browsing.
    func isShowing(_ current: String) -> Bool { index != nil && current == recalled }

    /// Adds a line that was sent, and ends any browsing. An empty line, or a repeat of the newest entry, is not added.
    mutating func record(_ line: String) {
        index = nil
        guard line.contains(where: { !$0.isWhitespace }), entries.last != line else { return }
        entries.append(line)
        if entries.count > Self.limit { entries.removeFirst(entries.count - Self.limit) }
    }

    /// The entry before the one shown, given what the editor holds now; nil when there is none.
    mutating func older(than current: String) -> String? {
        guard !entries.isEmpty else { return nil }
        let start: Int
        if let index {
            if current != recalled { draft = current }
            start = index
        } else {
            draft = current
            start = entries.count
        }
        guard start > 0 else { return nil }
        index = start - 1
        recalled = entries[start - 1]
        return recalled
    }

    /// The entry after the one shown, or the draft past the newest; nil when not browsing, or when the shown entry was edited.
    mutating func newer(than current: String) -> String? {
        guard let index, current == recalled else { return nil }
        if index + 1 < entries.count {
            self.index = index + 1
            recalled = entries[index + 1]
            return recalled
        }
        self.index = nil
        return draft
    }
}
