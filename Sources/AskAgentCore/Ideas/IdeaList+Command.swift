internal import Foundation

/// `/notes` and its `:subcommands` (roadmap 0180): adding, listing, showing, editing, deleting, and searching notes.
extension IdeaList {
    public struct Edit: Equatable, Sendable {
        public let id: Int
        /// The new text, verbatim after the id and one space; nil to start editing.
        public let text: String?

        public init(id: Int, text: String?) {
            self.id = id
            self.text = text
        }
    }

    public enum Command: Equatable, Sendable {
        case list(all: Bool)
        case show(Int)
        case edit(Edit)
        case delete(Int)
        case search(String)
        case add(String)
        case usage
    }

    /// Parses `/notes` or `/notes:<subcommand>` with `arguments`.
    public static func parse(command: String = "notes", arguments: String) -> Command {
        switch command {
            case "notes:all":
                return arguments.isBlank ? .list(all: true) : .usage
            case "notes:show":
                guard let id = noteID(arguments) else { return .usage }
                return .show(id)
            case "notes:edit":
                guard let edit = editing(arguments) else { return .usage }
                return .edit(edit)
            case "notes:delete":
                guard let id = noteID(arguments) else { return .usage }
                return .delete(id)
            case "notes:search":
                let query = arguments.trimmingCharacters(in: .whitespacesAndNewlines)
                return query.isEmpty ? .usage : .search(query)
            case "notes:add":
                return arguments.isBlank ? .usage : .add(arguments)
            case "notes":
                let trimmed = arguments.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty { return .list(all: false) }
                if trimmed.lowercased() == "all" { return .list(all: true) }
                if let id = noteID(trimmed) { return .show(id) }
                return .add(arguments)
            default:
                return .usage
        }
    }

    /// Note ID from a single token such as `n8` (or `i8`).
    public static func noteID(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains(where: \.isWhitespace),
            let first = trimmed.first, first == "n" || first == "i",
            let id = Int(trimmed.dropFirst()), id > 0
        else { return nil }
        return id
    }

    /// What `/notes:edit ARGUMENTS` edits, when the arguments start with an id such as `n3` (or `i3`).
    public static func editing(_ arguments: String) -> Edit? {
        let trimmed = arguments.drop(while: \.isWhitespace)
        let head = trimmed.prefix { !$0.isWhitespace }
        guard let first = head.first, first == "n" || first == "i", let id = Int(head.dropFirst()), id > 0 else {
            return nil
        }
        let rest = trimmed.dropFirst(head.count)
        return Edit(id: id, text: rest.isEmpty ? nil : String(rest.dropFirst()))
    }

    /// The draft that edits note `id`: the command, its id, and its text to change.
    public func draft(editing id: Int) -> String? { idea(id).map { "/notes:edit \($0.name) \($0.text)" } }
}
