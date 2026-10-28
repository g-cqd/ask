import Testing

@testable import AskAgentCore

@Suite("ui.interruptKeys, ui.escapeInterruptRequiresConfirmation and ui.interruptSendsQueued (roadmap 0083)")
struct InterruptConfigurationTests {
    private func ui(_ json: String) throws -> UISection {
        try ConfigurationFile.parse(Array(#"{"ui": \#(json)}"#.utf8), path: "c.json").ui ?? UISection()
    }

    @Test func `they are read and described`() throws {
        let section = try ui(
            #"{"interruptKeys": "ctrl-c", "escapeInterruptRequiresConfirmation": "off", "interruptSendsQueued": "next"}"#
        )
        #expect(section.interruptKeys == .ctrlC)
        #expect(section.escapeInterruptRequiresConfirmation == false)
        #expect(section.interruptSendsQueued == .next)
        #expect(
            section.description
                == "interruptKeys ctrl-c, escapeInterruptRequiresConfirmation off, interruptSendsQueued next")
    }

    @Test func `a later layer replaces only what it sets`() {
        let base = UISection(interruptKeys: .esc, interruptSendsQueued: .all)
        let layered = base.layered(with: UISection(interruptSendsQueued: QueuedAfterInterruptPreference.none))
        #expect(layered.interruptKeys == .esc && layered.interruptSendsQueued == QueuedAfterInterruptPreference.none)
    }

    @Test(arguments: [
        #"{"interruptKeys": "enter"}"#, #"{"interruptSendsQueued": "some"}"#,
        #"{"escapeInterruptRequiresConfirmation": "maybe"}"#
    ])
    func `a wrong value is refused`(json: String) {
        #expect(throws: (any Error).self) { try ui(json) }
    }

    @Test func `the keys are listed for the editor`() {
        for key in ["interruptKeys", "escapeInterruptRequiresConfirmation", "interruptSendsQueued"] {
            #expect(UISection.keys.contains(key))
        }
    }
}
