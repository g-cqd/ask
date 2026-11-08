import Testing

@testable import AskAgentCore

/// `ui.sessionTint`: where the session's colour shows, once it has one (`ui.sessionColor`): the status line and the input's box
/// (`both`, the default), one of them, or `none`; refused by name otherwise. It replaces `ui.inputBorder`.
@Suite("ui.sessionTint")
struct SessionTintConfigurationTests {
    private func ui(_ json: String) throws -> UISection? {
        try ConfigurationFile.parse(Array(#"{"ui": \#(json)}"#.utf8), path: "c.json").ui
    }

    @Test func `it is read, layered, listed and shown`() throws {
        let section = try #require(try ui(#"{"sessionTint": "status"}"#))
        #expect(section.sessionTint == .status && section.value(forKey: "sessionTint") == "status")
        var lower = UISection()
        lower.sessionTint = SessionTintPreference.none
        #expect(lower.layered(with: UISection()).sessionTint == SessionTintPreference.none)
        #expect(lower.layered(with: section).sessionTint == .status)
        #expect(UISection.keys.contains("sessionTint") && UISection().sessionTint == nil)
        #expect(!UISection.keys.contains("inputBorder"))
    }

    @Test func `another word is refused, naming the key`() {
        #expect(
            throws: ConfigurationError.outOfRange(
                path: "c.json",
                key: "ui.sessionTint",
                reason: #"is "all": use "both", "status", "input" or "none""#
            )
        ) { try ui(#"{"sessionTint": "all"}"#) }
    }
}
