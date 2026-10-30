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
        let section = try ui(#"{"inputPrefix": ""}"#)
        #expect(section.prompt == "" && !section.isEmpty)
        #expect(section.description == #"inputPrefix """#)
    }

    @Test func `a layer that sets one replaces it and leaves the others`() {
        let base = UISection(prompt: "a> ", tint: true)
        let over = UISection(tint: false)
        let layered = base.layered(with: over)
        #expect(layered.prompt == "a> " && layered.tint == false)
    }

    @Test func `the description lists them`() {
        #expect(
            UISection(prompt: "$ ", tint: false, separator: true).description
                == #"inputPrefix "$ ", tint false, separator true"#
        )
    }

    @Test(arguments: [
        "tint", "separator", "durations", "leaveFinishedJob", "listAllModels", "localizedDurations",
        "abortTurnRequiresConfirmation"
    ])
    func `a value that is not one of the key's is refused by name`(key: String) {
        #expect(throws: (any Error).self) { try ui(#"{"\#(key)": "maybe"}"#) }
    }
    @Test func `duration localization is parsed layered and shown`() throws {
        let base = try ui(#"{"durations":"words","tint":false}"#)
        let override = try ui(#"{"durations":"clock"}"#)
        #expect(!override.isEmpty && override.localizedDurations == false)
        #expect(override.description == "durations clock")
        #expect(UISection.keys.contains("durations"))
        #expect(base.layered(with: override).description == "tint false, durations clock")
    }

    @Test func `spinner preference is parsed, layered and shown`() throws {
        let base = try ui(#"{"spinner": "braille", "tint": false}"#)
        let override = try ui(#"{"spinner": "random"}"#)
        #expect(base.spinner == .braille)
        #expect(override.spinner == .random)
        #expect(override.description == "spinner random")
        #expect(UISection.keys.contains("spinner"))
        #expect(base.layered(with: override).description == "tint false, spinner random")
    }

    @Test func `job safety settings are parsed layered and shown`() throws {
        let base = try ui(#"{"leaveFinishedJob":true,"stopTwice":["esc"]}"#)
        let override = try ui(#"{"leaveFinishedJob":false,"stopTwice":["esc","ctrl-c"]}"#)
        #expect(base.jobAutoReturnWhenFocused == true && base.abortTurnRequiresConfirmation == false)
        #expect(!override.isEmpty)
        #expect(base.layered(with: override) == override)
        #expect(base.layered(with: UISection()) == base)
        #expect(override.description == "leaveFinishedJob false, stopTwice esc, ctrl-c")
        #expect(UISection.keys.contains("leaveFinishedJob") && UISection.keys.contains("stopTwice"))
    }

    @Test func `an unknown spinner style is rejected`() {
        #expect(throws: (any Error).self) { try ui(#"{"spinner": "bouncing_ball"}"#) }
    }

    @Test func `appearance is read, layered, shown, and refused when unknown`() throws {
        let base = try ui(#"{"appearance": "light", "tint": true}"#)
        #expect(base.appearance == .light && base.value(forKey: "appearance") == "light")
        #expect(base.description == "tint true, appearance light")
        #expect(base.layered(with: try ui(#"{"appearance": "auto"}"#)).appearance == .auto)
        let dark = try ui(#"{"appearance": "dark"}"#)
        #expect(UISection.keys.contains("appearance") && !dark.isEmpty)
        #expect(throws: (any Error).self) { try ui(#"{"appearance": "sepia"}"#) }
    }
}
