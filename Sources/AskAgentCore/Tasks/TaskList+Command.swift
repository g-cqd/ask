internal import Foundation

/// `/tasks` (ADR-0140): what the person reads of the list.
extension TaskList {
    /// The answer to `/tasks ARGUMENTS`: the tasks not done, `all`, or one task as `t3` or `3`.
    public func answer(to arguments: String) -> String {
        let wanted = arguments.trimmingCharacters(in: .whitespaces).lowercased()
        switch wanted {
            case "": return listing(all: false)
            case "all": return listing(all: true)
            default:
                guard let id = Int(wanted.hasPrefix("t") ? String(wanted.dropFirst()) : wanted) else {
                    return "Usage: /tasks, /tasks all, or /tasks t3 for one task."
                }
                return showing(id) ?? "There is no task t\(id)."
        }
    }
}
