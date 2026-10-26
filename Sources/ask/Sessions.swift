internal import ArgumentParser
internal import AskAgentCore
internal import Foundation

/// `ask sessions`: this project's sessions, the one written last first, with how each began.
struct Sessions: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List this project's sessions, newest first, for --resume.")

    @Option(help: "How many to list.")
    var limit = 20

    func run() {
        let listed = SessionDirectory(
            project: FileManager.default.currentDirectoryPath, environment: LaunchEnvironment.values
        )
        .sessions()
        guard !listed.isEmpty else {
            print("No sessions in this project yet.")
            return
        }
        let format = Date.FormatStyle(date: .abbreviated, time: .shortened)
        for listing in listed.prefix(Swift.max(1, limit)) {
            let summary = SessionSummary(readingFrom: listing.path)
            let prompts = summary.map { $0.prompts == 1 ? "1 prompt" : "\($0.prompts) prompts" } ?? "unreadable"
            let first = summary?.firstPrompt.map { Self.oneLine($0, limit: 60) } ?? ""
            print("\(listing.name)  \(listing.modified.formatted(format))  \(prompts)  \(first)")
        }
    }

    /// `text` on one line, cut to `limit` characters with an ellipsis.
    static func oneLine(_ text: String, limit: Int) -> String {
        let flat = text.split(whereSeparator: \.isNewline).joined(separator: " ")
        return flat.count <= limit ? flat : String(flat.prefix(limit - 1)) + "…"
    }
}
