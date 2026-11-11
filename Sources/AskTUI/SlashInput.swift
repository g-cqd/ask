internal import Foundation

/// What a submitted line is: a prompt for the model, or a command.
///
/// A line is a command when its first word is a slash and a command-shaped name: `/config`, `/reload now`, `/notes:edit n1`.
/// `/skill:debugging` is a skill invocation in a prompt, not a slash command.
/// `/Users/me/file.swift explain this` is a prompt, because its first word is a path, and so is anything that
/// does not start with a slash. A prompt that must begin with a command-shaped word starts with two slashes:
/// `//config` is sent as `/config`. A line starting with `!` is a command for the person's own shell, `!!` one whose result goes to the
/// model, and `\!` a message starting with `!`.
public enum SlashInput: Sendable, Equatable {
    case prompt(String)
    case command(name: String, arguments: String)
    /// `!command`: run it in the person's shell (note n56); with `!!`, its result is sent to the model.
    case shell(String, sends: Bool)

    /// Reads `line`.
    public init(_ line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        // `!` runs a command in the person's shell, `!!` sends its result too (note n56); `\!` sends a message that starts with `!`.
        if trimmed.hasPrefix("\\!") {
            self = .prompt(String(trimmed.dropFirst()))
            return
        }
        if trimmed.hasPrefix("!") {
            let sends = trimmed.hasPrefix("!!")
            self = .shell(String(trimmed.dropFirst(sends ? 2 : 1)).trimmingCharacters(in: .whitespaces), sends: sends)
            return
        }
        if trimmed.hasPrefix("//") {
            self = .prompt(String(trimmed.dropFirst()))
            return
        }
        guard trimmed.hasPrefix("/") else {
            self = .prompt(line)
            return
        }
        let word = trimmed.prefix { !$0.isWhitespace }
        let name = word.dropFirst()
        guard !name.hasPrefix("skill:"),
            let first = name.first, first.isLowercase, first.isASCII,
            let last = name.last, last != ":",
            name.allSatisfy({ ($0.isLowercase || $0.isNumber || $0 == "-" || $0 == ":") && $0.isASCII })
        else {
            self = .prompt(line)
            return
        }
        self = .command(
            name: String(name),
            arguments: String(trimmed.dropFirst(word.count)).trimmingCharacters(in: .whitespaces)
        )
    }
}
