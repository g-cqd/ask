/// Turns a call's changes into one change to keep (ADR-0141): planned in order on a copy of the list, each checked against the limits
/// and the list as the changes before it left it; what is already so changes nothing; one refusal refuses the call.
public struct TaskPlanner {
    struct Refusal: Error {
        let reason: String
    }

    var list: TaskList
    var report = TaskReport()
    private var changes: [TaskChange] = []
    /// The ids of the call's adds, in order, for `@1`, `@2`, ….
    private var adds: [Int] = []
    private var resolvedCount = 0
    let time: Int

    private init(list: TaskList, time: Int) {
        self.list = list
        self.time = time
    }

    /// The change to keep for `edits` on `list` at `time` (nil when everything was already so), and what to answer.
    public static func plan(
        _ edits: [TaskEdit],
        on list: TaskList,
        at time: Int
            // @dl:accept -- the tasks and the ideas are two lists of one store (ADR-0141): their reads, inputs, tools and records share a shape over different fields
    ) throws(ListPlanError) -> (change: TaskChange?, report: TaskReport) {
        guard !edits.isEmpty, edits.count <= ListLimits.changesPerCall else {
            throw ListPlanError(
                index: 0,
                operation: "",
                reason: "a call holds 1 to \(ListLimits.changesPerCall) changes."
            )
        }
        var planner = TaskPlanner(list: list, time: time)
        for (offset, edit) in edits.enumerated() {
            do {
                try planner.plan(edit)
            } catch {
                throw ListPlanError(index: offset + 1, operation: edit.operation, reason: error.reason)
            }
        }
        let changes = planner.changes
        return (changes.count > 1 ? .batch(changes) : changes.first, planner.report)
    }

    private mutating func plan(_ asked: TaskEdit) throws(Refusal) {
        switch asked {
            case .add(let draft): try add(draft)
            case .edit(let ref, let title, let detail, let tags):
                try edit(ref, title: title, detail: detail, tags: tags)
            case .state(let refs, let state): try set(refs, state)
            case .move(let ref, let placement): try move(ref, placement)
            case .link(let refs, let blockedBy, let related): try link(refs, blockedBy, related, adding: true)
            case .unlink(let refs, let blockedBy, let related): try link(refs, blockedBy, related, adding: false)
            case .remove(let refs): try remove(refs)
        }
    }

    /// Makes `change` on the copy, and keeps it for the batch.
    mutating func make(_ change: TaskChange) throws(Refusal) {
        do {
            try list.apply(change)
        } catch {
            throw Refusal(reason: Self.words(error))
        }
        changes.append(change)
    }

    /// The ids `refs` name, in order, once each; a removed task's id only where `removed` allows it.
    mutating func resolve(_ refs: [ListRef], removed: Bool = false) throws(Refusal) -> [Int] {
        let ids = try ListRef.expand(refs, adds: adds) { Refusal(reason: $0) }
        resolvedCount += ids.count
        guard resolvedCount <= ListLimits.idsPerCall else {
            throw Refusal(reason: "a call names at most \(ListLimits.idsPerCall) ids, ranges counted whole.")
        }
        for id in ids where list.task(id) == nil && !(removed && id < list.nextID) {
            throw Refusal(reason: "there is no task t\(id).")
        }
        return ids
    }

    /// The one id `ref` names.
    mutating func resolveOne(_ ref: ListRef) throws(Refusal) -> Int {
        let ids = try resolve([ref])
        guard ids.count == 1 else { throw Refusal(reason: "it takes one task, not a range.") }
        return ids[0]
    }

    /// The task an add made, or found already made, as the next `@n`.
    mutating func record(added id: Int) { adds.append(id) }

    static func words(_ error: TaskListError) -> String {
        switch error {
            case .unknownTask(let id): "there is no task t\(id)."
            case .emptyTitle: "a task needs a title."
            case .cycle: "that would make a task wait on itself."
            case .taken(let id): "t\(id) was given already."
            case .nested: "a batch cannot hold a batch."
        }
    }
}
