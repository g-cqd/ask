import Testing

@testable import AskAgentCore

/// The `threads` section (roadmap 0195): its limits, and how long a merged thread stays in the sidebar.
@Suite("The threads section reads its limits and how long merged threads stay listed")
struct ThreadsSectionTests {
    private func threads(_ json: String) throws -> ThreadsSection? {
        try ConfigurationFile.parse(Array(#"{"threads": \#(json)}"#.utf8), path: "test").threads
    }

    @Test func `mergedShownFor takes minutes, hours, days, or always`() throws {
        #expect(try threads(#"{"mergedShownFor": "30m"}"#)?.mergedListing == .seconds(1_800))
        #expect(try threads(#"{"mergedShownFor": "2h"}"#)?.mergedListing == .seconds(7_200))
        #expect(try threads(#"{"mergedShownFor": "1d"}"#)?.mergedListing == .seconds(86_400))
        #expect(try threads(#"{"mergedShownFor": "always"}"#)?.mergedListing == nil, "always: never left out")
        #expect(ThreadsSection().mergedListing == .seconds(86_400), "a day when nothing says")
    }

    @Test func `anything else is refused with what it takes`() {
        for value in ["soon", "0m", "5", "-1h", "1w"] {
            #expect(throws: ConfigurationError.self, "\(value)") { try threads(#"{"mergedShownFor": "\#(value)"}"#) }
        }
    }
}
