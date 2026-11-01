import Testing

@testable import AskAgentCore

@Suite("ui.fold.outputLines and ui.fold.outputBytes say when a tool's output folds its middle")
struct OutputFoldConfigurationTests {
    private func parse(_ text: String) throws(ConfigurationError) -> ConfigurationFile {
        try ConfigurationFile.parse(Array(text.utf8), path: "c.json")
    }

    @Test func `a file reads both keys and reports them under their names`() throws {
        let file = try parse("{ui:{fold:{outputLines:120,outputBytes:16384}}}")
        #expect(file.ui?.outputFoldLines == 120 && file.ui?.outputFoldBytes == 16384)
        #expect(file.ui?.description == "fold.outputLines 120, fold.outputBytes 16384")
        #expect(file.ui?.value(forKey: "fold.outputLines") == "120")
    }

    @Test func `too few lines or bytes are refused by name`() {
        #expect(
            throws: ConfigurationError.outOfRange(
                path: "c.json",
                key: "ui.fold.outputLines",
                reason: "must be at least 2"
            )
        ) { try parse("{ui:{fold:{outputLines:1}}}") }
        #expect(
            throws: ConfigurationError.outOfRange(
                path: "c.json",
                key: "ui.fold.outputBytes",
                reason: "must be at least 64"
            )
        ) { try parse("{ui:{fold:{outputBytes:63}}}") }
    }

    @Test func `a layer replaces each without forgetting the other`() {
        let user = ConfigurationFile(ui: UISection(outputFoldLines: 80, outputFoldBytes: 4096))
        let project = ConfigurationFile(ui: UISection(outputFoldBytes: 8192))
        let combined = Configuration.defaults.applying(user, from: .file("u")).applying(project, from: .file("p"))
        #expect(combined.ui.value.outputFoldLines == 80 && combined.ui.value.outputFoldBytes == 8192)
    }

    @Test func `the catalog lists both with their defaults`() {
        let names = SettingCatalog.all.map { $0.path.joined(separator: ".") }
        #expect(names.contains("ui.fold.outputLines") && names.contains("ui.fold.outputBytes"))
    }
}
