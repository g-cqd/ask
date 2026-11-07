import Testing

@testable import AskAgentCore

/// `ui.dim` (note n13): how faint secondary text is: `normal` (the default), `faint` or `fainter`; refused by name otherwise.
@Suite("ui.dim")
struct DimConfigurationTests {
    private func ui(_ json: String) throws -> UISection? {
        try ConfigurationFile.parse(Array(#"{"ui": \#(json)}"#.utf8), path: "c.json").ui
    }

    @Test func `it is read, layered, listed and shown`() throws {
        let section = try #require(try ui(#"{"dim": "fainter"}"#))
        #expect(section.dim == .fainter && section.value(forKey: "dim") == "fainter")
        var lower = UISection()
        lower.dim = .faint
        #expect(lower.layered(with: UISection()).dim == .faint)
        #expect(UISection.keys.contains("dim") && UISection().dim == nil)
    }

    @Test func `another word is refused, naming the key`() {
        #expect(
            throws: ConfigurationError.outOfRange(
                path: "c.json",
                key: "ui.dim",
                reason: #"is "ghost": use "normal", "faint" or "fainter""#
            )
        ) { try ui(#"{"dim": "ghost"}"#) }
    }
}
