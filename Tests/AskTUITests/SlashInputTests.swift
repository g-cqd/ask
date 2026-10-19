import Testing

@testable import AskTUI

/// What a submitted line means: a command only when its first word is a slash and a command-shaped name.
@Suite("A line is a command only when it starts with a command-shaped slash word")
struct SlashInputTests {
    @Test(arguments: [
        ("/config", "config", ""),
        ("/reload now", "reload", "now"),
        ("  /compact  focus on the tests  ", "compact", "focus on the tests"),
        ("/reload-config", "reload-config", ""),
        ("/h2", "h2", "")
    ])
    func `command-shaped words are commands, with their arguments`(line: String, name: String, arguments: String) {
        #expect(SlashInput(line) == .command(name: name, arguments: arguments))
    }

    @Test(arguments: [
        "fix the build", "/Users/me/file.swift explain this", "/etc/hosts", "/", "/ config", "/Config", "/-x",
        "/9lives",
        "/café", "explain /config please"
    ])
    func `anything else is a prompt, unchanged`(line: String) {
        #expect(SlashInput(line) == .prompt(line))
    }

    @Test func `two slashes send a prompt that begins with one`() {
        #expect(SlashInput("//config is how I set it") == .prompt("/config is how I set it"))
        #expect(SlashInput("//") == .prompt("/"))
    }
}
