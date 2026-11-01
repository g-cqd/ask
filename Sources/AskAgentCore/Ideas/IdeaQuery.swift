public import Foundation

/// A `read` of the ideas (ADR-0141), in the shape of the tasks' read.
public struct IdeaQuery: Sendable, Equatable {
    public enum View: String, Sendable, CaseIterable {
        // @dl:accept -- the tasks and the ideas are two lists of one store (ADR-0141): their reads, inputs, tools and records share a shape over different fields
        case new, open, all, summary
    }

    public var view: View
    public var ids: [ListRef]
    /// Words that must all appear in an idea's text.
    public var text: String?
    public var limit: Int

    public init(
        view: View = .open,
        ids: [ListRef] = [],
        text: String? = nil,
        limit: Int = ListLimits.defaultReadLimit
    ) {
        self.view = view
        self.ids = ids
        self.text = text
        self.limit = limit
    }

    public func answer(_ list: IdeaList, in zone: TimeZone = .current) throws(ListPlanError) -> String {
        guard (1 ... ListLimits.readLimit).contains(limit) else {
            throw TaskQuery.refusal("limit is 1 to \(ListLimits.readLimit).")
        }
        if let text, text.count > ListLimits.textLength { throw TaskQuery.refusal("text has at most 80 characters.") }
        guard !list.ideas.isEmpty else { return "No ideas yet." }
        var chosen = try select(list)
        if let text { chosen = ListSearch.rank(chosen, words: text) { [$0.text] } }
        if view == .summary {
            return "\(chosen.count) ideas: "
                + IdeaState.allCases.map { state in "\(chosen.count { $0.state == state }) \(state.rawValue)" }
                .joined(separator: ", ")
        }
        guard !chosen.isEmpty else { return "No idea matches." }
        let shown = chosen.prefix(limit)
        let full = !ids.isEmpty
        var lines = shown.map { full ? list.whole($0, in: zone) : list.line($0, in: zone) }
        if chosen.count > shown.count {
            lines.append("(\(chosen.count - shown.count) more; raise limit, or narrow the read.)")
        }
        return (list.newCount > 0 && ids.isEmpty ? "\(list.newCount) new.\n" : "")
            + lines.joined(separator: full ? "\n\n" : "\n")
    }

    private func select(_ list: IdeaList) throws(ListPlanError) -> [Idea] {
        guard !ids.isEmpty else {
            return list.ideas.filter { idea in
                switch view {
                    case .new: idea.state == .new
                    case .open: idea.state.isOpen
                    case .all, .summary: true
                }
            }
        }
        let wanted = try ListRef.expand(ids, adds: nil) { TaskQuery.refusal($0) }
        if let missing = wanted.first(where: { list.idea($0) == nil }) {
            throw TaskQuery.refusal("there is no idea i\(missing).")
        }
        return list.ideas.filter { Set(wanted).contains($0.id) }
    }
}
