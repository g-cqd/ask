internal import Foundation
internal import Testing

/// The architecture records keep the shape the documentation law gives them.
///
/// The law says a decision changed by evidence becomes a new record that supersedes the old one, and that the
/// chain is walkable in both directions. Diaries, the roadmap and the white paper were policed by tests; the
/// records were not, so a superseded record could name a successor that did not exist and nothing would say so.
@Suite("The architecture records keep their shape")
struct ADRLayoutTests {
    private static func record(_ number: String, status: String, extra: String = "") -> (name: String, text: String) {
        (name: "\(number)-title.md", text: "---\nstatus: \(status)\n\(extra)---\n\n# \(number) — Title\n")
    }

    @Test func `sound records have no problems`() {
        let records = [
            Self.record("0001", status: "superseded", extra: "superseded-by: ADR-0002\n"),
            Self.record("0002", status: "accepted", extra: "supersedes: ADR-0001\n")
        ]
        #expect(DocumentationLayout.adrProblems(in: records).isEmpty)
    }

    @Test func `a record with no status is reported`() {
        let record = (name: "0001-title.md", text: "# 0001 — Title\n")
        #expect(DocumentationLayout.adrProblems(in: [record]).count == 1)
    }

    @Test func `a status other than accepted or superseded is reported`() {
        let problems = DocumentationLayout.adrProblems(in: [Self.record("0001", status: "maybe")])
        #expect(problems.count == 1)
        #expect(problems.first?.contains("maybe") == true)
    }

    @Test func `a file name without a four digit number is reported`() {
        let record = (name: "title.md", text: "---\nstatus: accepted\n---\n")
        #expect(DocumentationLayout.adrProblems(in: [record]).count == 1)
    }

    @Test func `two records with one number are reported`() {
        let records = [
            Self.record("0001", status: "accepted"), (name: "0001-other.md", text: "---\nstatus: accepted\n---\n")
        ]
        #expect(DocumentationLayout.adrProblems(in: records).count == 1)
    }

    @Test func `a superseded record must name its successor`() {
        let problems = DocumentationLayout.adrProblems(in: [Self.record("0001", status: "superseded")])
        #expect(problems.count == 1)
    }

    @Test func `a successor that does not exist is reported`() {
        let records = [Self.record("0001", status: "superseded", extra: "superseded-by: ADR-0009\n")]
        #expect(DocumentationLayout.adrProblems(in: records).count == 1)
    }

    @Test func `a successor that does not name its predecessor back is reported`() {
        let records = [
            Self.record("0001", status: "superseded", extra: "superseded-by: ADR-0002\n"),
            Self.record("0002", status: "accepted")
        ]
        #expect(DocumentationLayout.adrProblems(in: records).count == 1)
    }

    @Test func `every record in the repository is sound`() throws {
        let files = try DocumentationLayout.adrFiles()
        let records = try files.map { (name: $0.lastPathComponent, text: try String(contentsOf: $0, encoding: .utf8)) }
        #expect(!records.isEmpty)
        let problems = DocumentationLayout.adrProblems(in: records)
        #expect(problems.isEmpty, "\(problems.joined(separator: "\n"))")
    }
}
