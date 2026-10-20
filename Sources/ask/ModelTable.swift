internal import AskAI
internal import Foundation

/// A model list as a table: what the server states, and `unknown` for what it does not.
enum ModelTable {
    /// Prints `snapshot`'s notices to standard error and its models to standard output.
    /// - Parameters:
    ///   - snapshot: the models and the notices about how they were read.
    ///   - defaultFirst: whether the first model is the server's choice of default, so it is marked `*`. Only Codex's list says so.
    static func print(_ snapshot: CatalogSnapshot, defaultFirst: Bool) {
        for notice in snapshot.notices { FileHandle.standardError.write(Data("ask: \(notice)\n".utf8)) }
        let reasoning = snapshot.models.contains { !$0.reasoningLevels.isEmpty }
        Swift.print(
            "MODEL".padding(toLength: 32, withPad: " ", startingAt: 0)
                + "CONTEXT".padding(toLength: 14, withPad: " ", startingAt: 0)
                + "OUTPUT" + (reasoning ? "        REASONING" : ""))
        for (index, model) in snapshot.models.enumerated() {
            let id = (defaultFirst ? (index == 0 ? "* " : "  ") : "") + model.id
            let context = model.contextWindow.map(String.init) ?? "unknown"
            let output = model.maxOutputTokens.map(String.init) ?? "unknown"
            Swift.print(
                id.padding(toLength: Swift.max(32, id.count + 1), withPad: " ", startingAt: 0)
                    + context.padding(toLength: 14, withPad: " ", startingAt: 0)
                    + (reasoning
                        ? output.padding(toLength: 14, withPad: " ", startingAt: 0) + model.reasoningDescription
                        : output))
        }
    }
}
