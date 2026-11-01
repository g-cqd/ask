/// The limits of ADR-0141 on what a change writes.
extension TaskPlanner {
    static func check(title: String, in list: TaskList? = nil, except id: Int? = nil) throws(Refusal) {
        guard !title.isBlank else { throw Refusal(reason: "a task needs a title.") }
        guard !title.contains(where: \.isNewline) else {
            throw Refusal(reason: "a title is one line; put the rest in detail.")
        }
        guard title.count <= ListLimits.titleLength else {
            throw Refusal(reason: "a title has at most \(ListLimits.titleLength) characters; put the rest in detail.")
        }
        if let other = list?.tasks.first(where: { $0.title == title && $0.id != id }) {
            throw Refusal(reason: "\(other.name) already has this title.")
        }
    }

    static func check(detail: String) throws(Refusal) {
        guard detail.count <= ListLimits.detailLength else {
            throw Refusal(reason: "a detail has at most \(ListLimits.detailLength) characters.")
        }
    }

    /// `tags` sorted, once each.
    static func check(tags: [String]) throws(Refusal) -> [String] {
        let unique = Array(Set(tags)).sorted()
        guard unique.count <= ListLimits.tagsPerTask else {
            throw Refusal(reason: "a task has at most \(ListLimits.tagsPerTask) tags.")
        }
        if let bad = unique.first(where: { !ListLimits.isName($0) }) {
            throw Refusal(reason: "tag \"\(bad)\" is not [a-z0-9-], 1 to \(ListLimits.nameLength) characters.")
        }
        return unique
    }
}
