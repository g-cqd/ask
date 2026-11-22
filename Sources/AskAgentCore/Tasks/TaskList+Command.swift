internal import Foundation

/// `/tasks` (ADR-0140): what the person reads of the list.
extension TaskList {
    /// The answer to `/tasks ARGUMENTS`: the tasks not done, `all`, or one task as `t3` or `3`. `spent` says what a done task cost
    /// (roadmap 0239), after its line; the model's `tasks` tool does not say it, so its reads cost no more.
    public func answer(to arguments: String, spent: (SessionTask) -> String? = { _ in nil }) -> String {
        let wanted = arguments.trimmingCharacters(in: .whitespaces).lowercased()
        switch wanted {
            case "": return listing(all: false)
            case "all": return listing(all: true, spent: spent)
            default:
                guard let id = Int(wanted.hasPrefix("t") ? String(wanted.dropFirst()) : wanted) else {
                    return "Usage: /tasks, /tasks all, or /tasks t3 for one task."
                }
                guard let shown = showing(id) else { return "There is no task t\(id)." }
                return task(id).flatMap(spent).map { shown + "\nspent " + $0 } ?? shown
        }
    }
}
