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
            case "tree": return treeRows()
            case "thinking": return await thinkingRows()
            case "login": return LoginChoices.rows()
            case "logout": return logoutRows()
            default: return []
        }
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
                ChoiceRow(label: record.name, detail: "\(record.provider.rawValue) connection", arguments: record.name))
        }
        for account in accounts where !account.removable {
            // Not ask's to forget: said, so the person knows why it is not in the list.
            rows.append(
                ChoiceRow(
                    label: "· \(account.target)", detail: "\(account.method): unset it in your shell", arguments: ""))
        }
        if !rows.isEmpty {
            rows.append(ChoiceRow(label: "all", detail: "every account ask has stored", arguments: "all"))
        }
        return rows
    }
}
