internal import AskAI
internal import Foundation

/// A model list as a table: what the server reports, and `unknown` for what it does not.
enum ModelTable {
    /// Prints notices to standard error and descriptors to standard output. Only Codex's priority order chooses a default.
    /// `showAll` lists the models the `ui.onlyUsefulModels` filter hides too, with the reason; so does the setting being off. When it
    /// hides some, the last line says how many, so nothing leaves the list unannounced.
    static func print(_ full: CatalogSnapshot, defaultFirst: Bool, showAll: Bool = false) {
        NamedConnections.report(full.notices)
        let filtering = !showAll && ModelFilter.onlyUseful()
        let snapshot = CatalogSnapshot(
            models: ModelUsefulness.shown(full.models, onlyUseful: filtering), notices: full.notices)
        defer { reportHidden(full.models, filtering: filtering) }
        let efforts = snapshot.models.contains { !$0.reasoningLevels.isEmpty }
        let modes = snapshot.models.contains { $0.supportsThinking != nil || !$0.thinkingModes.isEmpty }
        var headers = ["MODEL", "CONTEXT", "OUTPUT"]
        var widths = [32, 14, 14]
        if efforts {
            headers.append("REASONING")
            widths.append(44)
        }
        let reasons = snapshot.models.contains { $0.unsuitable != nil }
        let images = snapshot.models.contains { $0.acceptsImages != nil }
        if images {
            headers.append("IMAGES")
            widths.append(44)
        }
        if reasons {
            headers.append("NOT USEFUL FOR ASK")
            widths.append(28)
        }
        if modes {
            headers.append("THINKING MODES")
            widths.append(0)
        }
        let firstUseful = snapshot.models.firstIndex { $0.unsuitable == nil } ?? 0
        Swift.print(row(headers, widths: widths))
        for (index, model) in snapshot.models.enumerated() {
            let mark = defaultFirst ? (index == firstUseful ? "* " : "  ") : ""
            var columns = [
                mark + model.id, model.contextWindow.map(String.init) ?? "unknown",
                model.maxOutputTokens.map(String.init) ?? "unknown"
            ]
            if efforts { columns.append(model.reasoningDescription) }
            if images { columns.append(imageDescription(model)) }
            if reasons { columns.append(model.unsuitable ?? "") }
            if modes { columns.append(thinkingModes(model)) }
            Swift.print(row(columns, widths: widths))
        }
    }

    private static func reportHidden(_ models: [CatalogModel], filtering: Bool) {
        let hidden = ModelUsefulness.hidden(models)
        guard filtering, !hidden.isEmpty else { return }
        let reasons = Dictionary(grouping: hidden, by: { $0.unsuitable ?? "" }).sorted { $0.key < $1.key }
            .map { "\($0.value.count) \($0.key)" }.joined(separator: ", ")
        Swift.print(
            "\(hidden.count) more hidden (\(reasons)): `ask models NAME --all` lists them, `ui.onlyUsefulModels off` allows them."
        )
    }

    private static func row(_ columns: [String], widths: [Int]) -> String {
        columns.enumerated()
            .map { index, value in
                index == columns.count - 1
                    ? value
                    : value.padding(toLength: Swift.max(widths[index], value.count + 1), withPad: " ", startingAt: 0)
            }
            .joined()
    }

    private static func imageDescription(_ model: CatalogModel) -> String {
        switch model.acceptsImages {
            case nil: "unknown"
            case false: "no"
            case true: model.imageLimits.map { "yes (\($0.summary))" } ?? "yes"
        }
    }

    private static func thinkingModes(_ model: CatalogModel) -> String {
        if model.supportsThinking == false { return "none" }
        return model.thinkingModes.isEmpty ? "unknown" : model.thinkingModes.map(\.rawValue).joined(separator: " ")
    }
}
