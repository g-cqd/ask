/// The model's changes to the notes (ADR-0141): it marks them, and says which task one became; it never writes or edits one. Planned on a
/// copy, all or nothing, what is already so changing nothing.
public struct IdeaPlanner {
    /// `ideas` (ids, ranges) marked `state`, and linked to `task` when given, which must be in the task list.
    public struct Mark: Sendable, Equatable {
        public var ideas: [ListRef]
        public var state: IdeaState
        public var task: ListRef?

        public init(ideas: [ListRef], state: IdeaState, task: ListRef? = nil) {
            self.ideas = ideas
            self.state = state
            self.task = task
        }
    }

    private struct Refusal: Error {
        let reason: String
    }

    private var list: IdeaList
    private let tasks: TaskList?
    private var changes: [IdeaChange] = []
    private var marked: [IdeaState: [Int]] = [:]
    private var linked: [Int] = []
    private var already: [Int] = []
    private var count = 0

    /// The change to keep (nil when everything was already so), and what to answer.
    public static func plan(
        _ marks: [Mark],
        on list: IdeaList,
        tasks: TaskList?
            // @dl:accept -- the tasks and the ideas are two lists of one store (ADR-0141): their reads, inputs, tools and records share a shape over different fields
    ) throws(ListPlanError) -> (change: IdeaChange?, answer: String) {
        guard !marks.isEmpty, marks.count <= ListLimits.changesPerCall else {
            throw ListPlanError(
                index: 0,
                operation: "",
                reason: "a call holds 1 to \(ListLimits.changesPerCall) changes."
            )
        }
        var planner = IdeaPlanner(list: list, tasks: tasks)
        for (offset, mark) in marks.enumerated() {
            do {
                try planner.plan(mark)
            } catch {
                throw ListPlanError(index: offset + 1, operation: "mark", reason: error.reason)
            }
        }
        return (planner.changes.count > 1 ? .batch(planner.changes) : planner.changes.first, planner.answer)
    }

    private init(list: IdeaList, tasks: TaskList?) {
        self.list = list
        self.tasks = tasks
    }

    private mutating func plan(_ mark: Mark) throws(Refusal) {
        let ids = try resolve(mark.ideas)
        let task = try mark.task.map { ref throws(Refusal) in try resolveTask(ref) }
        for id in ids {
            var made: [IdeaChange] = []
            if list.idea(id)?.state != mark.state {
                made.append(.state(id: id, mark.state))
                marked[mark.state, default: []].append(id)
            }
            if let task, list.idea(id)?.tasks.contains(task) == false {
                made.append(.link(id: id, task: task))
                linked.append(id)
            }
            for change in made { try? list.apply(change) }
            changes += made
            if made.isEmpty { already.append(id) }
        }
    }

    private var answer: String {
        let parts =
            IdeaState.allCases.compactMap { state in
                marked[state].map { ListRef.counted(state.rawValue, $0, prefix: "n") }
            }
            + (linked.isEmpty ? [] : [ListRef.counted("linked", linked, prefix: "n")])
            + (already.isEmpty ? [] : [ListRef.counted("already so:", already, prefix: "n")])
        return parts.isEmpty ? "Nothing to change." : parts.joined(separator: " · ")
    }

    private mutating func resolve(_ refs: [ListRef]) throws(Refusal) -> [Int] {
        let ids = try ListRef.expand(refs, adds: nil) { Refusal(reason: $0) }
        count += ids.count
        guard count <= ListLimits.idsPerCall else {
            throw Refusal(reason: "a call names at most \(ListLimits.idsPerCall) ids.")
        }
        if let missing = ids.first(where: { list.idea($0) == nil }) {
            throw Refusal(reason: "there is no note n\(missing).")
        }
        var seen: Set<Int> = []
        return ids.filter { seen.insert($0).inserted }
    }

    private func resolveTask(_ ref: ListRef) throws(Refusal) -> Int {
        guard case .id(let id) = ref else { throw Refusal(reason: "task takes one task's id, such as t3.") }
        guard let tasks, tasks.task(id) != nil else { throw Refusal(reason: "there is no task t\(id).") }
        return id
    }
}
