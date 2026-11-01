internal import AskAI
internal import AskAgentCore
internal import AskTUI
internal import Foundation
internal import Synchronization

extension AgentConversation {
    /// The lists the commands offer after their names.
    func choices(for command: String) async -> [ChoiceRow] {
        switch command {
            case "model":
                let model = current.withLock { $0.settings.model }
                return await ModelChoices.rows(current: model, environment: LaunchEnvironment.values)
            case "config":
                let user = configEditorPath(.user)
                let project = configEditorPath(.project)
                return [
                    ChoiceRow(label: "user", detail: user.path, arguments: "user"),
                    ChoiceRow(label: "project", detail: project.path, arguments: "project")
                ]
            case "resume": return sessionRows()
            case "rewind", "tree": return treeRows()
            case "thinking": return await thinkingRows()
            case "login": return LoginChoices.rows()
            case "logout": return logoutRows()
            case "encrypt":
                return [
                    ChoiceRow(label: "on", detail: "encrypt this session's file", arguments: "on"),
                    ChoiceRow(label: "off", detail: "keep it unencrypted", arguments: "off")
                ]
            case "tasks": return taskRows()
            case "ideas": return ideaRows()
            case "#": return referenceRows()
            default: return []
        }
    }

    /// Each task, to show it in full, and the whole list with the done ones.
    private func taskRows() -> [ChoiceRow] {
        guard let list = try? SessionTasks.board.current() else { return [] }
        return Self.listRows(list.tasks.map { ($0.name, list.line($0)) }, all: "every task, done ones too")
    }

    /// The tasks not done and the ideas still open, for `#` (roadmap 0186): `#t3` and `#i2`, each with its line.
    private func referenceRows() -> [ChoiceRow] {
        let tasks =
            ((try? SessionTasks.board.current()) ?? nil)
            .map { list in
                list.tasks.filter { $0.state != .done }.map { (name: "#" + $0.name, line: list.line($0)) }
            } ?? []
        let ideas =
            ((try? SessionTasks.ideas.current()) ?? nil)
            .map { list in
                list.ideas.filter(\.state.isOpen).map { (name: "#" + $0.name, line: list.line($0)) }
            } ?? []
        return (tasks + ideas)
            .map {
                ChoiceRow(label: $0.name, detail: String($0.line.drop { $0 != " " }.dropFirst()), arguments: $0.name)
            }
    }

    /// A list's rows: `all`, then each entry by its name, its line after the name as the detail; none for an empty list.
    static func listRows(_ entries: [(name: String, line: String)], all: String) -> [ChoiceRow] {
        guard !entries.isEmpty else { return [] }
        let rows = entries.map {
            ChoiceRow(label: $0.name, detail: String($0.line.dropFirst($0.name.count + 1)), arguments: $0.name)
        }
        return [ChoiceRow(label: "all", detail: all, arguments: "all")] + rows
    }

    /// The accounts that can be forgotten, each as the name that forgets it, and everything at once.
    private func logoutRows() -> [ChoiceRow] {
        let environment = LaunchEnvironment.values
        let accounts =
            (try? CredentialFile.standard(environment: environment).signedInAccounts(environment: environment)) ?? []
        var rows = accounts.filter(\.removable)
            .map { ChoiceRow(label: $0.target, detail: $0.method, arguments: $0.target) }
        for record in (try? NamedConnections.registry(environment: environment).list().records) ?? [] {
            rows.append(
                ChoiceRow(label: record.name, detail: "\(record.provider.rawValue) connection", arguments: record.name)
            )
        }
        for account in accounts where !account.removable {
            // Not ask's to forget: said, so the person knows why it is not in the list.
            rows.append(
                ChoiceRow(
                    label: "· \(account.target)",
                    detail: "\(account.method): unset it in your shell",
                    arguments: ""
                )
            )
        }
        if !rows.isEmpty {
            rows.append(ChoiceRow(label: "all", detail: "every account ask has stored", arguments: "all"))
        }
        return rows
    }
}
