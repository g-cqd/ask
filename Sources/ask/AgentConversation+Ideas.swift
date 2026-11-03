internal import AskAgentCore
internal import AskTUI
internal import Foundation

/// `/notes` and its `:subcommands` (roadmap 0180): the person's notes, saved at once, during a turn too, without reaching the model.
extension AgentConversation {
    static let notesUsage =
        "Usage: /notes to pick or list, /notes TEXT (or /notes:add TEXT) to add, /notes:all, /notes:show n3, /notes:edit n3, /notes:delete n3, /notes:search TEXT."

    /// `/notes` and `/notes:all`, `/notes:show`, `/notes:edit`, `/notes:add`, `/notes:delete`, `/notes:search`.
    func notes(command: String = "notes", arguments: String, update: @Sendable (ConversationUpdate) -> Void) {
        switch IdeaList.parse(command: command, arguments: arguments) {
            case .list(let all):
                update(.notice(Self.ideasText { $0.listing(all: all) }, isError: false))
            case .show(let id):
                update(
                    .notice(
                        Self.ideasText { $0.showing(id) ?? "There is no note n\(id)." },
                        isError: (try? SessionTasks.ideas.current())??.idea(id) == nil
                    )
                )
            case .edit(let edit):
                editNote(edit, update: update)
            case .delete(let id):
                changeIdeas(update: update) { _ in
                    .remove(id: id)
                } then: { list in
                    update(.choices(command: "notes", rows: Self.ideaRows(list)))
                    return "Deleted n\(id)."
                }
            case .search(let query):
                update(.notice(Self.ideasText { $0.searching(query) }, isError: false))
            case .add(let text):
                saveIdea(text, update: update)
            case .usage:
                update(.notice(Self.notesUsage, isError: true))
        }
    }

    /// Keeps `text` as typed, timestamped.
    func saveIdea(_ text: String, update: @Sendable (ConversationUpdate) -> Void) {
        guard !text.isEmpty else {
            update(.notice(Self.notesUsage, isError: true))
            return
        }
        // Before the first prompt there is no session to keep it with yet: held, and saved when the session starts (owner, 2026-11-02).
        if SessionTasks.waitsForSession {
            let made = Self.now
            SessionTasks.ideas.hold { $0.adding(text, at: made) }
            update(
                .notice(
                    "Kept: it is saved to your notes when the session starts, with your first prompt.",
                    isError: false
                )
            )
            return
        }
        changeIdeas(update: update) {
            $0.adding(text, at: Self.now)
        } then: { list in
            "Saved note \(list.ideas.last?.name ?? "")."
        }
    }

    /// Saves the notes typed before the session started, now that it has, and says so.
    func saveHeldIdeas(update: @Sendable (ConversationUpdate) -> Void) {
        do {
            let made = try SessionTasks.ideas.applyHeld()
            guard let list = made.last else { return }
            let names = list.ideas.suffix(made.count).map(\.name).joined(separator: ", ")
            update(
                .notice(
                    "Saved the note\(made.count == 1 ? "" : "s") typed before the session started: \(names).",
                    isError: false
                )
            )
        } catch {
            update(.notice("The notes typed before the session started could not be saved: \(error)", isError: true))
        }
    }

    private func editNote(_ edit: IdeaList.Edit, update: @Sendable (ConversationUpdate) -> Void) {
        guard let text = edit.text else {
            guard let draft = (try? SessionTasks.ideas.current())??.draft(editing: edit.id) else {
                update(.notice("There is no note n\(edit.id).", isError: true))
                return
            }
            update(.editDraft(draft))
            return
        }
        changeIdeas(update: update) { _ in
            .edit(id: edit.id, text: text, at: Self.now)
        } then: { list in
            update(.choices(command: "notes", rows: Self.ideaRows(list)))
            update(.fillDraft("/notes "))
            return "Edited n\(edit.id)."
        }
    }

    /// Each note, to show or act on it, and every one with the fulfilled and dismissed.
    func ideaRows(includeAll: Bool = true) -> [ChoiceRow] {
        guard let list = try? SessionTasks.ideas.current() else { return [] }
        return Self.ideaRows(list, includeAll: includeAll)
    }

    /// The newest first.
    private static func ideaRows(_ list: IdeaList, includeAll: Bool = true) -> [ChoiceRow] {
        let rows = listRows(
            list.ideas.reversed().map { ($0.name, list.line($0)) },
            all: "every note, fulfilled and dismissed ones too"
        )
        return includeAll ? rows : Array(rows.dropFirst())
    }

    private func changeIdeas(
        update: @Sendable (ConversationUpdate) -> Void,
        _ make: (IdeaList) -> IdeaChange,
        then done: (IdeaList) -> String
    ) {
        do {
            guard let list = try SessionTasks.ideas.change(make) else {
                update(.notice(SessionTasks.unavailable, isError: true))
                return
            }
            update(.notice(done(list), isError: false))
        } catch let error as IdeaListError {
            update(.notice(Self.words(error), isError: true))
        } catch {
            update(.notice("The notes could not be changed: \(error)", isError: true))
        }
    }

    private static func ideasText(_ text: (IdeaList) -> String) -> String {
        do {
            if let list = try SessionTasks.ideas.current() { return text(list) }
        } catch {
            return "The notes could not be read: \(error)"
        }
        return SessionTasks.unavailable
    }

    private static func words(_ error: IdeaListError) -> String {
        switch error {
            case .unknownIdea(let id): "There is no note n\(id)."
            case .emptyText: "A note cannot be empty."
            case .taken(let id): "n\(id) was given already."
            case .nested: "The notes file holds a record it cannot read."
        }
    }

    private static var now: Int { Int(Date().timeIntervalSince1970) }
}
