import Testing

@testable import AskAgentCore

/// `ui.sidebarLayout` (notes n39, n40): where the open sidebar goes, `full` beside the transcript, `bottom` in the band with the input,
/// or `adaptive`, the default, which picks by the screen's width.
@Suite("ui.sidebarLayout says where the open sidebar goes")
struct UISidebarLayoutTests {
    private func ui(_ json: String) throws -> UISection? {
        try ConfigurationFile.parse(Array(#"{"ui": \#(json)}"#.utf8), path: "test").ui
    }

    @Test func `adaptive unless it says full or bottom, and nothing else`() throws {
        #expect(UISection().sidebarPlacement == "adaptive")
        #expect(try ui(#"{"sidebarLayout": "bottom"}"#)?.sidebarPlacement == "bottom")
        #expect(try ui(#"{"sidebarLayout": "full"}"#)?.sidebarPlacement == "full")
        #expect(throws: ConfigurationError.self) { try ui(#"{"sidebarLayout": "middle"}"#) }
        let layered = UISection().layered(with: try #require(try ui(#"{"sidebarLayout": "full"}"#)))
        #expect(layered.sidebarPlacement == "full")
    }
}
