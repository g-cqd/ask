/// Each operation of ADR-0141 planned: what it changes, and what is already so.
extension TaskPlanner {
    mutating func add(_ draft: TaskDraft) throws(Refusal) {
        try Self.check(title: draft.title)
        try Self.check(detail: draft.detail)
        let tags = try Self.check(tags: draft.tags)
        let blockedBy = try resolve(draft.blockedBy)
        let related = try resolve(draft.related)
        // A title names one task: the same title and detail is that task, whatever the changes since did to its state, tags and links,
        // so a repeated add finds it rather than resetting it.
        if let existing = list.tasks.first(where: { $0.title == draft.title }) {
            guard existing.detail == draft.detail else {
                throw Refusal(
                    reason:
                        "\(existing.name) already has this title, with other contents: edit it, or choose another title."
                )
            }
            report.already.append(existing.id)
            record(added: existing.id)
            return
        }
        guard list.tasks.count < ListLimits.entries else {
            throw Refusal(reason: "a list holds at most \(ListLimits.entries) tasks.")
        }
        let task = SessionTask(
            id: list.nextID,
            title: draft.title,
            detail: draft.detail,
            state: draft.state,
            blockedBy: blockedBy,
            related: related,
            tags: tags,
            made: time,
            closed: draft.state == .done ? time : nil
        )
        try make(.add(task))
        report.added.append(task.id)
        record(added: task.id)
    }

    mutating func edit(_ ref: ListRef, title: String?, detail: String?, tags: [String]?) throws(Refusal) {
        guard title != nil || detail != nil || tags != nil else {
            throw Refusal(reason: "edit takes a title, a detail or tags.")
        }
        let id = try resolveOne(ref)
        guard let task = list.task(id) else { return }
        if let title { try Self.check(title: title, in: list, except: id) }
        if let detail { try Self.check(detail: detail) }
        let newTitle = title.flatMap { $0 == task.title ? nil : $0 }
        let newDetail = detail.flatMap { $0 == task.detail ? nil : $0 }
        let newTags = try tags.map { tags throws(Refusal) in try Self.check(tags: tags) }
            .flatMap { $0 == task.tags ? nil : $0 }
        if newTitle != nil || newDetail != nil { try make(.edit(id: id, title: newTitle, detail: newDetail)) }
        if let newTags { try make(.tags(id: id, newTags)) }
        if newTitle == nil, newDetail == nil, newTags == nil {
            report.already.append(id)
        } else {
            report.edited.append(id)
        }
    }

    mutating func set(_ refs: [ListRef], _ state: TaskState) throws(Refusal) {
        for id in try resolve(refs) {
            guard list.task(id)?.state != state else {
                report.already.append(id)
                continue
            }
            try make(.state(id: id, state, at: state == .done ? time : nil))
            report.states[state, default: []].append(id)
        }
    }

    mutating func move(_ ref: ListRef, _ placement: TaskPlacement) throws(Refusal) {
        let id = try resolveOne(ref)
        let next: Int
        let after: Bool
        switch placement {
            case .before(let target): (next, after) = (try resolveOne(target), false)
            case .end:
                guard let last = list.tasks.last?.id, last != id else {
                    report.already.append(id)
                    return
                }
                (next, after) = (last, true)
        }
        guard id != next else { throw Refusal(reason: "a task cannot move next to itself.") }
        var moved = list
        try? moved.apply(.place(id: id, next: next, after: after))
        guard moved.tasks.map(\.id) != list.tasks.map(\.id) else {
            report.already.append(id)
            return
        }
        try make(.place(id: id, next: next, after: after))
        report.moved.append(id)
    }

    mutating func link(_ refs: [ListRef], _ blockedBy: [ListRef], _ related: [ListRef], adding: Bool) throws(Refusal) {
        guard !blockedBy.isEmpty || !related.isEmpty else {
            throw Refusal(reason: "it takes blocked_by, related, or both.")
        }
        let ids = try resolve(refs)
        let targets = [(TaskLink.blockedBy, try resolve(blockedBy)), (.related, try resolve(related))]
        for id in ids {
            var changed = false
            for (kind, others) in targets {
                for other in others { changed = try connect(id, kind, other, adding: adding) || changed }
            }
            if changed {
                if adding { report.linked.append(id) } else { report.unlinked.append(id) }
            } else {
                report.already.append(id)
            }
        }
    }

    /// Whether linking or unlinking `id` and `other` changed anything.
    private mutating func connect(_ id: Int, _ kind: TaskLink, _ other: Int, adding: Bool) throws(Refusal) -> Bool {
        guard id != other else { throw Refusal(reason: "t\(id) cannot be linked to itself.") }
        let current = list.task(id).map { kind == .blockedBy ? $0.blockedBy : $0.related } ?? []
        guard current.contains(other) != adding else { return false }
        try make(adding ? .link(id: id, kind, target: other) : .unlink(id: id, kind, target: other))
        return true
    }

    mutating func remove(_ refs: [ListRef]) throws(Refusal) {
        for id in try resolve(refs, removed: true) {
            guard list.task(id) != nil else {
                report.already.append(id)
                continue
            }
            try make(.remove(id: id))
            report.removed.append(id)
        }
    }
}
