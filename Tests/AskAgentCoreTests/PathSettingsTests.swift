import Testing

@testable import AskAgentCore

/// `ui.paths` and `ui.pathAncestors` (roadmap 0215): paths in replies shown `short` (the default) or `asWritten`; and how many folders
/// above the project a common one may be, 2 by default, `null` for no limit.
@Suite("ui.paths and ui.pathAncestors")
struct PathSettingsTests {
    private func ui(_ json: String) throws -> UISection? {
        try ConfigurationFile.parse(Array(#"{"ui": \#(json)}"#.utf8), path: "c.json").ui
    }

    @Test func `they are read, layered, listed and shown`() throws {
        let section = try #require(try ui(#"{"paths": "asWritten", "pathAncestors": 0}"#))
        #expect(section.paths == .asWritten && section.value(forKey: "paths") == "asWritten")
        #expect(section.pathAncestors == 0 && section.value(forKey: "pathAncestors") == "0")
        let unlimited = try #require(try ui(#"{"pathAncestors": null}"#))
        #expect(
            unlimited.pathAncestors == UISection.noAncestorLimit && unlimited.value(forKey: "pathAncestors") == "null"
        )
        #expect(
            unlimited.layered(with: section).pathAncestors == 0
                && section.layered(with: UISection()).paths == .asWritten
        )
        #expect(UISection.keys.contains("paths") && UISection.keys.contains("pathAncestors"))
        #expect(UISection().paths == nil && UISection().pathAncestors == nil)
    }

    @Test func `a negative count and another word are refused, naming the key`() {
        #expect(throws: ConfigurationError.self) { try ui(#"{"pathAncestors": -2}"#) }
        #expect(
            throws: ConfigurationError.outOfRange(
                path: "c.json",
                key: "ui.paths",
                reason: #"is "long": use "short" or "asWritten""#
            )
        ) { try ui(#"{"paths": "long"}"#) }
    }
}
