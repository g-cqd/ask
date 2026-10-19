internal import Foundation

/// What a submitted line is: a prompt for the model, or a command.
///
/// A line is a command when its first word is a slash and a command-shaped name: `/config`, `/reload now`.
/// `/Users/me/file.swift explain this` is a prompt, because its first word is a path, and so is anything that
/// does not start with a slash. A prompt that must begin with a command-shaped word starts with two slashes:
/// `//config` is sent as `/config`.
public enum SlashInput: Sendable, Equatable {
    case prompt(String)
    case command(name: String, arguments: String)

    /// Reads `line`.
    public init(_ line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
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
        guard let first = name.first, first.isLowercase, first.isASCII,
            name.allSatisfy({ ($0.isLowercase || $0.isNumber || $0 == "-") && $0.isASCII })
        else {
            self = .prompt(line)
            return
        }
        self = .command(
            name: String(name),
            arguments: String(trimmed.dropFirst(word.count)).trimmingCharacters(in: .whitespaces))
    }
}
