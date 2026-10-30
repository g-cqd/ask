import Testing

@testable import AskAgentCore

/// The `ui` section (ADR-0046): what it accepts, how the layers combine, and what it says when it is wrong.
@Suite("The ui section sets how the screen treats the mouse and tool output")
struct UIConfigurationTests {
    private func parse(_ text: String) throws(ConfigurationError) -> ConfigurationFile {
        try ConfigurationFile.parse(Array(text.utf8), path: "c.json")
    }

    @Test func `every key is read, in JSON5`() throws {
        let file = try parse(
            """
            {
              // the mouse belongs to the terminal here
              ui: { mouse: false, copyOnSelect: false, tools: 'open', thinking: 'folded', scrollLines: 5, },
            }
            """)
        #expect(
            file.ui
                == UISection(mouse: false, copyOnSelect: false, foldTools: false, foldThinking: true, scrollLines: 5))
        #expect(file.sets("ui") && !ConfigurationFile().sets("ui"))
    }

    @Test func `a switch is "on" or "off", or true or false, whichever way it is written`() throws {
        let words = try parse(
            "{ui: {mouse: 'off', copyOnSelect: 'on', tint: 'off', padding: 'on', markdown: 'off'}, skills: {enabled: 'off'}}"
        )
        #expect(words.ui == UISection(mouse: false, copyOnSelect: true, tint: false, padding: true, markdown: false))
        #expect(words.skills?.enabled == false)
        let flags = try parse("{ui: {mouse: false, tint: false, onlyUsefulModels: true}, skills: {enabled: true}}")
        #expect(flags.ui == UISection(mouse: false, tint: false, onlyUsefulModels: true))
        #expect(flags.skills?.enabled == true)
        #expect(throws: ConfigurationError.self) { try parse("{ui: {mouse: 'yes'}}") }
    }

    @Test func `folded is a tool setting, and so is open`() throws {
        #expect(try parse("{ui: {tools: 'folded'}}").ui?.foldTools == true)
        #expect(try parse("{ui: {tools: 'open'}}").ui?.foldTools == false)
    }

    @Test func `thinking and tools are set apart`() throws {
        let file = try parse("{ui: {thinking: 'open', tools: 'folded'}}")
        #expect(file.ui?.foldThinking == false && file.ui?.foldTools == true)
        #expect(
            throws: ConfigurationError.outOfRange(
                path: "c.json", key: "ui.thinking", reason: "is \"hidden\": use \"folded\" or \"open\"")
        ) { try parse("{ui: {thinking: 'hidden'}}") }
    }

    @Test func `an unknown key, a bad choice or a number below one is refused, naming the key`() {
        // A key ADR-0046 lists but that nothing reads yet is refused too, so a file never promises what is not there.
        #expect(
            throws: ConfigurationError.unknownKey(path: "c.json", key: "ui.images", known: ConfigurationFile.keys)
        ) { try parse("{ui: {images: 'open'}}") }
        #expect(
            throws: ConfigurationError.outOfRange(
                path: "c.json", key: "ui.tools", reason: "is \"hidden\": use \"folded\" or \"open\"")
        ) { try parse("{ui: {tools: 'hidden'}}") }
        #expect(
            throws: ConfigurationError.outOfRange(path: "c.json", key: "ui.scrollLines", reason: "must be at least 1")
        ) { try parse("{ui: {scrollLines: 0}}") }
    }

    @Test func `a wrong type is refused`() {
        #expect(throws: ConfigurationError.self) { try parse("{ui: {mouse: 'yes'}}") }
        #expect(throws: ConfigurationError.self) { try parse("{ui: {scrollLines: 'three'}}") }
    }

    @Test func `a layer replaces the keys it sets and leaves the others`() {
        let user = ConfigurationFile(ui: UISection(mouse: false, scrollLines: 5))
        let project = ConfigurationFile(ui: UISection(copyOnSelect: false, scrollLines: 2))
        let layered = Configuration.defaults.applying(user, from: .file("u")).applying(project, from: .file("p"))
        #expect(
            layered.ui.value == UISection(mouse: false, copyOnSelect: false, foldTools: nil, scrollLines: 2))
        #expect(layered.ui.source == .file("p"))
        // A layer that sets one key leaves what the layers below set for the rest.
        let third = layered.applying(ConfigurationFile(ui: UISection(mouse: true)), from: .file("q"))
        #expect(third.ui.value == UISection(mouse: true, copyOnSelect: false, foldTools: nil, scrollLines: 2))
    }

    @Test func `a file with no ui section leaves the setting and its source alone`() {
        let configuration = Configuration.defaults.applying(ConfigurationFile(model: "m"), from: .file("u"))
        #expect(configuration.ui == Configuration.defaults.ui)
        #expect(configuration.ui.source == .defaults)
    }

    @Test func `a reload names a ui change`() {
        let before = Configuration.defaults
        let after = before.applying(ConfigurationFile(ui: UISection(mouse: false)), from: .file("u"))
        let lines = after.changes(from: before)
        guard let line = lines.first, lines.count == 1 else {
            Issue.record("expected one change line, got \(lines)")
            return
        }
        #expect(line.hasPrefix("ui: ") && line.contains("mouse false"), "\(line)")
    }

    @Test func `the description says only what is set`() {
        #expect(UISection().description == "defaults")
        #expect(UISection(mouse: false, scrollLines: 4).description == "mouse false, scrollLines 4")
        #expect(UISection(foldTools: true).description == "fold.tools true")
        #expect(UISection(foldThinking: false).description == "fold.thinking false")
    }
}
