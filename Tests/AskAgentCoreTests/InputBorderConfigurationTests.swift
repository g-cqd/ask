import Testing

@testable import AskAgentCore

/// `ui.inputBorder` (note n36): the colour of the box around the input, `tint` (the session's colour, lighter; the default) or `dim`;
/// refused by name otherwise.
@Suite("ui.inputBorder")
struct InputBorderConfigurationTests {
    private func ui(_ json: String) throws -> UISection? {
        try ConfigurationFile.parse(Array(#"{"ui": \#(json)}"#.utf8), path: "c.json").ui
    }

    @Test func `it is read, layered, listed and shown`() throws {
        let section = try #require(try ui(#"{"inputBorder": "dim"}"#))
        #expect(section.inputBorder == .dim && section.value(forKey: "inputBorder") == "dim")
        var lower = UISection()
        lower.inputBorder = .tint
        #expect(lower.layered(with: UISection()).inputBorder == .tint)
        #expect(lower.layered(with: section).inputBorder == .dim)
        #expect(UISection.keys.contains("inputBorder") && UISection().inputBorder == nil)
    }

    @Test func `another word is refused, naming the key`() {
        #expect(
            throws: ConfigurationError.outOfRange(
                path: "c.json",
                key: "ui.inputBorder",
                reason: #"is "red": use "tint" or "dim""#
            )
        ) { try ui(#"{"inputBorder": "red"}"#) }
    }
}
