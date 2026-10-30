import Testing

@testable import AskAgentCore

@Suite("ui.onlyUsefulModels (roadmap 0089)")
struct OnlyUsefulModelsConfigurationTests {
    private func ui(_ json: String) throws -> UISection {
        try ConfigurationFile.parse(Array(#"{"ui": \#(json)}"#.utf8), path: "c.json").ui ?? UISection()
    }

    @Test func `it is read, described, and layered`() throws {
        let off = try ui(#"{"listAllModels": true}"#)
        #expect(off.onlyUsefulModels == false)
        #expect(off.description == "listAllModels true")
        #expect(try ui(#"{"onlyUsefulModels": "off"}"#).onlyUsefulModels == false, "the old name still reads")
        #expect(UISection(onlyUsefulModels: true).layered(with: off).onlyUsefulModels == false)
        #expect(off.layered(with: UISection()).onlyUsefulModels == false)
    }

    @Test func `it is unset by default, which the lists read as on`() {
        #expect(UISection().onlyUsefulModels == nil && UISection().isEmpty)
    }

    @Test func `a value that is not on or off is refused`() {
        #expect(throws: (any Error).self) { try ui(#"{"onlyUsefulModels": "maybe"}"#) }
    }
}
