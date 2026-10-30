import Testing

@testable import AskAgentCore

@Suite("ui.stopKeys, ui.stopTwice and ui.queuedOnStop (roadmaps 0083 and 0154)")
struct InterruptConfigurationTests {
    private func ui(_ json: String) throws -> UISection {
        try ConfigurationFile.parse(Array(#"{"ui": \#(json)}"#.utf8), path: "c.json").ui ?? UISection()
    }

    @Test func `they are read and described`() throws {
        let section = try ui(
            #"{"stopKeys": "ctrl-c", "stopTwice": [], "queuedOnStop": "next"}"#
        )
        #expect(section.interruptKeys == .ctrlC)
        #expect(section.escapeInterruptRequiresConfirmation == false && section.abortTurnRequiresConfirmation == false)
        #expect(section.interruptSendsQueued == .next)
        #expect(
            section.description == "stopKeys ctrl-c, stopTwice none, queuedOnStop next")
    }

    @Test func `a later layer replaces only what it sets`() {
        let base = UISection(interruptKeys: .esc, interruptSendsQueued: .all)
        let layered = base.layered(with: UISection(interruptSendsQueued: QueuedAfterInterruptPreference.none))
        #expect(layered.interruptKeys == .esc && layered.interruptSendsQueued == QueuedAfterInterruptPreference.none)
    }

    @Test(arguments: [
        #"{"stopKeys": "enter"}"#, #"{"queuedOnStop": "some"}"#, #"{"stopTwice": ["enter"]}"#,
        #"{"escapeInterruptRequiresConfirmation": "maybe"}"#, #"{"interruptKeys": "enter"}"#
    ])
    func `a wrong value is refused`(json: String) {
        #expect(throws: (any Error).self) { try ui(json) }
    }

    @Test func `the keys are listed for the editor`() {
        for key in ["stopKeys", "stopTwice", "queuedOnStop"] {
            #expect(UISection.keys.contains(key))
        }
    }
}
