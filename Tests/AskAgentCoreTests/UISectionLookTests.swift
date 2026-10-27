import Testing

@testable import AskAgentCore

/// The keys that set the screen's look (roadmap 0074): the prompt, the tint and the rule.
@Suite("ui.prompt, ui.tint and ui.separator are read, shown, layered and refused when wrong")
struct UISectionLookTests {
    private func ui(_ json: String) throws -> UISection {
        try ConfigurationFile.parse(Array(#"{"ui": \#(json)}"#.utf8), path: "c.json").ui ?? UISection()
    }

    @Test func `they are read`() throws {
        let section = try ui(#"{"prompt": "› ", "tint": "off", "separator": "on"}"#)
        #expect(section.prompt == "› " && section.tint == false && section.separator == true)
    }

    @Test func `an empty prompt is none, and is a setting`() throws {
        let section = try ui(#"{"prompt": ""}"#)
        #expect(section.prompt == "" && !section.isEmpty)
        #expect(section.description == "prompt none")
    }

    @Test func `a layer that sets one replaces it and leaves the others`() {
        let base = UISection(prompt: "a> ", tint: true)
        let over = UISection(tint: false)
        let layered = base.layered(with: over)
        #expect(layered.prompt == "a> " && layered.tint == false)
    }

    @Test func `the description lists them`() {
        #expect(
            UISection(prompt: "$ ", tint: false, separator: true).description == #"prompt "$ ", tint off, separator on"#
        )
    }

    @Test(arguments: ["tint", "separator", "localizedDurations"])
    func `a value that is not on or off is refused by name`(key: String) {
        #expect(throws: (any Error).self) { try ui(#"{"\#(key)": "maybe"}"#) }
    }
    @Test func `duration localization is parsed layered and shown`() throws {
        let base = try ui(#"{"localizedDurations":"on","tint":"off"}"#)
        let override = try ui(#"{"localizedDurations":"off"}"#)
        #expect(!override.isEmpty)
        #expect(override.description == "localizedDurations off")
        #expect(UISection.keys.contains("localizedDurations"))
        #expect(base.layered(with: override).description == "tint off, localizedDurations off")
    }
}
