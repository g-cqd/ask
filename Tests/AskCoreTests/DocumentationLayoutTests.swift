import Foundation
import Testing

import AskCore

@Suite("The diary stays within its line budget")
struct DiaryLineBudgetTests {
    @Test func `every diary file is within the line budget`() throws {
        let over = try DocumentationLayout.diaryFilesExceedingLines(DocumentationLayout.maximumDiaryLines)
        #expect(
            over.isEmpty,
            """
            These diary files exceed \(DocumentationLayout.maximumDiaryLines) lines and must roll \
            over to a new file:
            \(over.map { "  - \($0.url.lastPathComponent): \($0.lines) lines" }.joined(separator: "\n"))
            """
        )
    }

    @Test func `there is a diary directory to police`() throws {
        #expect(try DocumentationLayout.diaryDirectoryExists())
    }

    @Test func `a file exactly at the budget is allowed`() throws {
        // The ceiling is inclusive. Off-by-one on a rollover rule means a file can never reach its
        // own limit without the check demanding a split it cannot make.
        let lines = DocumentationLayout.maximumDiaryLines
        let url = try DocumentationLayout.fixtureDirectory().appending(path: "at-budget.md")
        try "#\n".appending(String(repeating: "x\n", count: lines - 1))
            .write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(try DocumentationLayout.lineCount(of: url) == lines)
        let over = try DocumentationLayout.filesExceedingLines(in: url.deletingLastPathComponent(), limit: lines)
        #expect(over.isEmpty)
    }
}

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