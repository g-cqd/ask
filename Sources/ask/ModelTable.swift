internal import AskAI
internal import Foundation

/// A model list as a table: what the server reports, and `unknown` for what it does not.
enum ModelTable {
    /// Prints notices to standard error and descriptors to standard output. Only Codex's priority order chooses a default.
    static func print(_ snapshot: CatalogSnapshot, defaultFirst: Bool) {
        NamedConnections.report(snapshot.notices)
        let efforts = snapshot.models.contains { !$0.reasoningLevels.isEmpty }
        let modes = snapshot.models.contains { $0.supportsThinking != nil || !$0.thinkingModes.isEmpty }
        var headers = ["MODEL", "CONTEXT", "OUTPUT"]
        var widths = [32, 14, 14]
        if efforts {
            headers.append("REASONING")
            widths.append(44)
        }
        if modes {
            headers.append("THINKING MODES")
            widths.append(0)
        }
        Swift.print(row(headers, widths: widths))
        for (index, model) in snapshot.models.enumerated() {
            let mark = defaultFirst ? (index == 0 ? "* " : "  ") : ""
            var columns = [
                mark + model.id, model.contextWindow.map(String.init) ?? "unknown",
                model.maxOutputTokens.map(String.init) ?? "unknown"
            ]
            if efforts { columns.append(model.reasoningDescription) }
            if modes { columns.append(thinkingModes(model)) }
            Swift.print(row(columns, widths: widths))
        }
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

    private static func thinkingModes(_ model: CatalogModel) -> String {
        if model.supportsThinking == false { return "none" }
        return model.thinkingModes.isEmpty ? "unknown" : model.thinkingModes.map(\.rawValue).joined(separator: " ")
    }
}
