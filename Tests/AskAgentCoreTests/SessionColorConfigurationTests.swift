import Testing

@testable import AskAgentCore

/// `ui.sessionColor` (roadmap 0164): off by default; `always` or `others`; refused by name otherwise.
@Suite("ui.sessionColor")
struct SessionColorConfigurationTests {
    private func ui(_ json: String) throws -> UISection? {
        try ConfigurationFile.parse(Array(#"{"ui": \#(json)}"#.utf8), path: "c.json").ui
    }

    @Test func `it is read, layered, listed and shown`() throws {
        let section = try #require(try ui(#"{"sessionColor": "always"}"#))
        #expect(section.sessionColor == .always && section.value(forKey: "sessionColor") == "always")
        #expect(UISection(sessionColor: .others).layered(with: UISection()).sessionColor == .others)
        #expect(UISection.keys.contains("sessionColor") && UISection().sessionColor == nil)
    }

    @Test func `another word is refused, naming the key`() {
        #expect(
            throws: ConfigurationError.outOfRange(
                path: "c.json", key: "ui.sessionColor", reason: #"is "blue": use "off", "always" or "others""#)
        ) { try ui(#"{"sessionColor": "blue"}"#) }
    }
}
