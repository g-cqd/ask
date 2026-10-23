import Testing

@testable import AskAgentCore

@Suite("ui.code and ui.codeFoldLines configure long code blocks")
struct CodeFoldConfigurationTests {
    private func parse(_ text: String) throws(ConfigurationError) -> ConfigurationFile {
        try ConfigurationFile.parse(Array(text.utf8), path: "c.json")
    }

    @Test func `a file reads both keys and reports them`() throws {
        let file = try parse("{ui:{code:'open',codeFoldLines:30}}")
        #expect(file.ui?.foldCode == false && file.ui?.codeFoldLines == 30)
        #expect(file.ui?.description == "code open, codeFoldLines 30")
    }

    @Test func `a bad choice or a length below one is refused by name`() {
        #expect(
            throws: ConfigurationError.outOfRange(
                path: "c.json", key: "ui.code", reason: "is \"hidden\": use \"folded\" or \"open\"")
        ) { try parse("{ui:{code:'hidden'}}") }
        #expect(
            throws: ConfigurationError.outOfRange(path: "c.json", key: "ui.codeFoldLines", reason: "must be at least 1")
        ) { try parse("{ui:{codeFoldLines:0}}") }
    }

    @Test func `a layer replaces them without forgetting the other ui keys`() {
        let user = ConfigurationFile(ui: UISection(mouse: false, codeFoldLines: 40))
        let project = ConfigurationFile(ui: UISection(foldCode: false))
        let combined = Configuration.defaults.applying(user, from: .file("u")).applying(project, from: .file("p"))
        #expect(combined.ui.value.codeFoldLines == 40 && combined.ui.value.foldCode == false)
        #expect(combined.ui.value.mouse == false)
    }
}
