internal import Foundation
internal import Testing

/// The roadmap's statuses and blockers stay true.
///
/// The documentation law says a stale `blocked-by` "sends someone to wait on work that already landed". It was
/// kept by hand, and four entries waited on roadmap 0013 for a day after it was done. A guard is cheaper than a
/// reminder, and a status the code contradicts is the same defect in a different field.
@Suite("The roadmap's statuses and blockers stay true")
struct RoadmapStatusTests {
    private static func entry(_ number: String, status: String, blockedBy: String = "[]") -> (
        name: String, text: String
    ) {
        (
            name: "\(number)-work.md",
            text: "---\nstatus: \(status)\nblocked-by: \(blockedBy)\n---\n\n# \(number) — Work\n"
        )
    }

    @Test func `sound entries have no problems`() {
        let entries = [
            Self.entry("0001", status: "done"),
            Self.entry("0002", status: "in-progress", blockedBy: "[]"),
            Self.entry("0003", status: "not-started", blockedBy: #"["0002"]"#)
        ]
        #expect(DocumentationLayout.roadmapProblems(in: entries).isEmpty)
    }

    @Test func `a status that is not one of the three is reported`() {
        let problems = DocumentationLayout.roadmapProblems(in: [Self.entry("0001", status: "finished")])
        #expect(problems.count == 1)
        #expect(problems.first?.contains("finished") == true)
    }

    @Test func `a missing status is reported`() {
        let entry = (name: "0001-work.md", text: "# 0001 — Work\n")
        #expect(DocumentationLayout.roadmapProblems(in: [entry]).count == 1)
    }

    @Test func `a blocker that does not exist is reported`() {
        let entries = [Self.entry("0001", status: "not-started", blockedBy: #"["0009"]"#)]
        #expect(DocumentationLayout.roadmapProblems(in: entries).count == 1)
    }

    @Test func `waiting on work that is done is reported`() {
        let entries = [
            Self.entry("0001", status: "done"),
            Self.entry("0002", status: "not-started", blockedBy: #"["0001"]"#)
        ]
        let problems = DocumentationLayout.roadmapProblems(in: entries)
        #expect(problems.count == 1)
        #expect(problems.first?.contains("0001") == true)
    }

    @Test func `a finished entry may keep the blockers it had`() {
        let entries = [
            Self.entry("0001", status: "in-progress"),
            Self.entry("0002", status: "done", blockedBy: #"["0001"]"#)
        ]
        #expect(DocumentationLayout.roadmapProblems(in: entries).isEmpty)
    }

    @Test func `two entries with one number are reported`() {
        let entries = [Self.entry("0001", status: "done"), (name: "0001-other.md", text: "---\nstatus: done\n---\n")]
        #expect(DocumentationLayout.roadmapProblems(in: entries).count == 1)
    }

    @Test func `a name without a four digit number is reported`() {
        let entry = (name: "work.md", text: "---\nstatus: done\n---\n")
        #expect(DocumentationLayout.roadmapProblems(in: [entry]).count == 1)
    }

    @Test func `every entry in the repository is sound`() throws {
        let entries = try DocumentationLayout.roadmapEntries()
            .map { (name: $0.url.lastPathComponent, text: $0.text) }
        #expect(!entries.isEmpty)
        let problems = DocumentationLayout.roadmapProblems(in: entries)
        #expect(problems.isEmpty, "\(problems.joined(separator: "\n"))")
    }
}
