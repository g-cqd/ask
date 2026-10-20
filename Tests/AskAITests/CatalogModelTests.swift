internal import Testing

@testable import AskAI

struct CatalogModelTests {
    @Test func `the levels are shown in the server's order with the default marked`() {
        let model = CatalogModel(id: "m", reasoningLevels: ["low", "medium", "high"], defaultReasoningLevel: "medium")
        #expect(model.reasoningDescription == "low medium* high")
    }

    @Test func `levels with no default are listed plainly, and no levels says unknown`() {
        #expect(CatalogModel(id: "m", reasoningLevels: ["low", "high"]).reasoningDescription == "low high")
        #expect(CatalogModel(id: "m").reasoningDescription == "unknown")
    }
}
