import Testing

@testable import AskAgentCore

@Suite("ui.promptRows is a positive layered input row cap")
struct PromptRowsConfigurationTests {
    @Test func `a file reads the row limit and reports it`() throws {
        let file = try ConfigurationFile.parse(Array("{ui:{promptRows:3}}".utf8), path: "c.json")
        #expect(file.ui?.promptRows == 3)
        #expect(file.ui?.description == "promptRows 3")
        #expect(file.ui?.isEmpty == false)
    }

    @Test(arguments: [0, -1])
    func `a nonpositive row count is refused by name`(rows: Int) {
        #expect(
            throws: ConfigurationError.outOfRange(path: "c.json", key: "ui.promptRows", reason: "must be at least 1")
        ) {
            try ConfigurationFile.parse(Array("{ui:{promptRows:\(rows)}}".utf8), path: "c.json")
        }
    }

    @Test func `a layer replaces the limit without forgetting other ui choices`() {
        let user = ConfigurationFile(ui: UISection(mouse: false, promptRows: 5))
        let project = ConfigurationFile(ui: UISection(promptRows: 2))
        let combined = Configuration.defaults.applying(user, from: .file("u")).applying(project, from: .file("p"))
        #expect(combined.ui.value.promptRows == 2 && combined.ui.value.mouse == false)
        let unrelated = combined.applying(ConfigurationFile(ui: UISection(foldThinking: false)), from: .file("q"))
        #expect(unrelated.ui.value.promptRows == 2)
    }
}
