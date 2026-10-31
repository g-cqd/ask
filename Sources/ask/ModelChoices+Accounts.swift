internal import AskAI
internal import AskTUI

/// A model several accounts of one subscription serve is one row of `/model` (roadmap 0092). Chosen, it runs with the account last chosen
/// for it; never chosen, it writes the model in the draft and lists its accounts, one row each, so the person picks one and it is kept.
extension ModelChoices {
    /// The rows of `groups`, each offered model looked up in `models` by account and id.
    static func rows(
        _ groups: [ModelOfferGroup], models: [String: [String: CatalogModel]], current: ResolvedModel,
        currentName: String,
        environment: [String: String]
    ) -> [ChoiceRow] {
        var rows: [ChoiceRow] = []
        for group in groups {
            let first = group.accounts[0]
            guard let model = models[first]?[group.model] else { continue }
            guard group.accounts.count > 1, let kind = group.kind else {
                rows.append(offer(model, provider: first, current: current, currentName: currentName))
                continue
            }
            let isCurrent = group.accounts.contains(currentName) && group.model == current.model
            let reveal = group.model + " "
            let accounts = group.accounts.joined(separator: " · ")
            if let chosen = ModelAccounts.memory(environment: environment).account(for: group.model, kind: kind),
                group.accounts.contains(chosen)
            {
                rows.append(
                    ChoiceRow(
                        label: group.model, detail: "\(chosen), of \(accounts) · a space after the model for another",
                        arguments: "\(chosen) \(group.model)", isCurrent: isCurrent))
            } else {
                rows.append(
                    ChoiceRow(
                        label: group.model, detail: "\(accounts) · choose the account next", arguments: group.model,
                        isCurrent: isCurrent, completes: true))
            }
            for account in group.accounts {
                guard let entry = models[account]?[group.model] else { continue }
                let row = offer(entry, provider: account, current: current, currentName: currentName)
                rows.append(
                    ChoiceRow(
                        label: "\(group.model) · \(account)", detail: row.detail, arguments: row.arguments,
                        isCurrent: row.isCurrent, revealedBy: reveal))
            }
        }
        return rows
    }
}
