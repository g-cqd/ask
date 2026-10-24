import Foundation

@testable import AskTUI

/// Slash commands from a table of `name | summary` lines, so a fixture is data and not another copy of the shape the real command
/// tables have.
func commandTable(_ lines: String) -> [SlashCommand] {
    lines.split(separator: "\n")
        .map { line in
            let parts = line.split(separator: "|", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            return SlashCommand(name: parts[0], summary: parts[1])
        }
}
