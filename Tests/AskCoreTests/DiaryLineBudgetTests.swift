import AskCore
import Foundation
import Testing

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
