internal import AskAgentCore
internal import AskTUI
internal import Foundation

/// `/idea` and `/ideas` (roadmap 0180): the person's ideas, saved at once, during a turn too, without reaching the model.
extension AgentConversation {
    /// `/idea TEXT`: keeps the text as typed, timestamped.
    func saveIdea(_ text: String, update: @Sendable (ConversationUpdate) -> Void) {
        guard !text.isEmpty else {
            update(.notice("Usage: /idea TEXT keeps an idea as typed; /ideas lists them.", isError: true))
            return
        }
        changeIdeas(update: update) {
            $0.adding(text, at: Self.now)
        } then: { list in
            "Saved idea \(list.ideas.last?.name ?? "")."
        }
    }

    /// `/ideas`, `/ideas all`, `/ideas i3` to edit one, `/ideas i3 TEXT` to keep the edit and go back to the list.
    func ideas(arguments: String, update: @Sendable (ConversationUpdate) -> Void) {
        guard let edit = IdeaList.editing(arguments) else {
            let all = arguments.lowercased() == "all"
            guard arguments.isEmpty || all else {
                update(.notice("Usage: /ideas, /ideas all, or /ideas i3 to edit one.", isError: true))
                return
            }
            update(.notice(Self.ideasText { $0.listing(all: all) }, isError: false))
            return
        }
        guard let text = edit.text else {
            guard let draft = (try? SessionTasks.ideas.current())??.draft(editing: edit.id) else {
                update(.notice("There is no idea i\(edit.id).", isError: true))
                return
            }
            update(.editDraft(draft))
            return
        }
        changeIdeas(update: update) { _ in
            .edit(id: edit.id, text: text, at: Self.now)
        } then: { list in
            update(.choices(command: "ideas", rows: Self.ideaRows(list)))
            update(.fillDraft("/ideas "))
            return "Edited i\(edit.id)."
        }
    }

    /// Each idea, to edit it, and every one with the fulfilled and dismissed.
    func ideaRows() -> [ChoiceRow] {
        guard let list = try? SessionTasks.ideas.current() else { return [] }
        return Self.ideaRows(list)
    }

    /// The newest first.
    private static func ideaRows(_ list: IdeaList) -> [ChoiceRow] {
        listRows(
            list.ideas.reversed().map { ($0.name, list.line($0)) },
            all: "every idea, fulfilled and dismissed ones too"
        )
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
            update(.notice("The ideas could not be changed: \(error)", isError: true))
        }
    }

    private static func ideasText(_ text: (IdeaList) -> String) -> String {
        do {
            if let list = try SessionTasks.ideas.current() { return text(list) }
        } catch {
            return "The ideas could not be read: \(error)"
        }
        return SessionTasks.unavailable
    }

    private static func words(_ error: IdeaListError) -> String {
        switch error {
            case .unknownIdea(let id): "There is no idea i\(id)."
            case .emptyText: "An idea cannot be empty."
            case .taken(let id): "i\(id) was given already."
        }
    }

    private static var now: Int { Int(Date().timeIntervalSince1970) }
}
