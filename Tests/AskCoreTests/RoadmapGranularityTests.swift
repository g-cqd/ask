import AskCore
import Foundation
import Testing

@Suite("A roadmap entry is one file")
struct RoadmapGranularityTests {
    @Test func `the roadmap is not empty`() throws {
        let entries = try DocumentationLayout.roadmapEntries()
        #expect(!entries.isEmpty, "the roadmap has no entries yet")
    }

    @Test func `every roadmap entry declares its status`() throws {
        let entries = try DocumentationLayout.roadmapEntries()
        for entry in entries {
            #expect(
                entry.declaresStatus,
                "\(entry.url.lastPathComponent) does not declare a `status:` field"
            )
        }
    }

    @Test func `no roadmap entry holds more than one entry`() throws {
        let entries = try DocumentationLayout.roadmapEntries()
        for entry in entries where entry.holdsMultipleEntries {
            Issue.record("\(entry.url.lastPathComponent) holds more than one roadmap entry")
        }
    }
}
