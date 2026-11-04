internal import ArgumentParser
internal import AskAgentCore
internal import Foundation

/// `ask sessions`: this project's sessions, the one written last first, with how each began.
struct Sessions: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List this project's sessions, newest first, for --resume."
    )

    @Option(help: "How many to list.")
    var limit = 20

    func run() {
        let listed = SessionDirectory(
            project: FileManager.default.currentDirectoryPath,
            environment: LaunchEnvironment.values
        )
        .sessions()
        guard !listed.isEmpty else {
            print("No sessions in this project yet.")
            return
        }
        let format = Date.FormatStyle(date: .abbreviated, time: .shortened)
        var shown = 0
        for listing in listed {
            guard shown < Swift.max(1, limit) else { break }
            let summary = SessionSummary(readingFrom: listing.path, keyring: SessionKeyAccess.keyring)
            // A thread's session is reached from its main's (roadmap 0195).
            if summary?.isThread == true { continue }
            shown += 1
            let prompts =
                summary.map { $0.isLocked ? "locked" : $0.prompts == 1 ? "1 prompt" : "\($0.prompts) prompts" }
                ?? "unreadable"
            let first = summary?.firstPrompt.map { Self.oneLine($0, limit: 60) } ?? ""
            print("\(listing.name)  \(listing.modified.formatted(format))  \(prompts)  \(first)")
        }
    }

    /// `text` on one line, cut to `limit` characters with an ellipsis.
    static func oneLine(_ text: String, limit: Int) -> String {
        SessionOutline.oneLine(text, limit: limit)
    }
}
