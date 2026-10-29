internal import AskAgentCore
internal import Testing

/// `ask config` shows every `ui` and `skills` key under the name a file uses, with the layer that set it (roadmap 0103).
@Suite("Every ui and skills key has a value and a source")
struct ConfigurationKeySourceTests {
    private static let full = UISection(
        mouse: true, copyOnSelect: false, foldTools: true, foldThinking: false, scrollLines: 3, promptRows: 6,
        foldCode: true,
        codeFoldLines: 20, sidebarOpen: false, prompt: "", tint: true, separator: true, padding: false,
        markdown: true, localizedDurations: true,
        spinner: .line, jobAutoReturnWhenFocused: true, abortTurnRequiresConfirmation: false, interruptKeys: .ctrlC,
        escapeInterruptRequiresConfirmation: true, interruptSendsQueued: .next, onlyUsefulModels: true,
        appearance: .auto)

    @Test func `a section that sets every key has a value for each of them`() {
        let missing = UISection.keys.filter { Self.full.value(forKey: $0) == nil }
        #expect(missing.isEmpty, "keys with no value: \(missing)")
    }

    @Test func `values are written as a file writes them`() {
        #expect(Self.full.value(forKey: "copyOnSelect") == "off")
        #expect(Self.full.value(forKey: "tools") == "folded")
        #expect(Self.full.value(forKey: "thinking") == "open")
        #expect(Self.full.value(forKey: "sidebar") == "closed")
        #expect(Self.full.value(forKey: "prompt") == "none")
        #expect(Self.full.value(forKey: "interruptKeys") == "ctrl-c")
        #expect(Self.full.value(forKey: "interruptSendsQueued") == "next")
        #expect(UISection().value(forKey: "tint") == nil)
    }

    @Test func `each key keeps the layer that set it, and the rest are defaults`() {
        let configuration = Configuration.defaults
            .applying(
                ConfigurationFile(ui: UISection(tint: false), skills: SkillsSection(maxAdvertised: 8)),
                from: .file("user")
            )
            .applying(ConfigurationFile(ui: UISection(padding: false)), from: .file("project"))
        #expect(configuration.source(ofKey: "ui.tint") == .file("user"))
        #expect(configuration.source(ofKey: "ui.padding") == .file("project"))
        #expect(configuration.source(ofKey: "ui.mouse") == .defaults)
        #expect(configuration.source(ofKey: "skills.maxAdvertised") == .file("user"))
        #expect(configuration.source(ofKey: "skills.enabled") == .defaults)
    }
}
