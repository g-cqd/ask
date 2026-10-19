import AemiIO
import Foundation
import System
import Testing

@testable import AskAgentCore

/// Opening a damaged session repairs it in memory (ADR-0013); the user has to be told, in words that name the line.
@Suite("A repaired session says so, and what was repaired")
struct SessionRepairNoticeTests {
    private let directory = FileManager.default.temporaryDirectory.appending(path: "ask-repair-\(UUID().uuidString)")
    private let header = "{\"type\":\"session\",\"version\":1}\n"
    private let entry = "{\"id\":\"a\",\"payload\":{\"kind\":\"user\",\"text\":\"x\"},\"type\":\"entry\"}\n"

    private func recorder(_ text: String) throws -> SessionRecorder {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "\(UUID().uuidString).jsonl")
        try Data(text.utf8).write(to: url)
        return SessionRecorder(try SessionFile.open(at: FilePath(url.path), durability: .none))
    }

    @Test func `an undamaged session has nothing to report`() throws {
        let clean = try recorder(header + entry)
        #expect(clean.issues.isEmpty && clean.repairNotice == nil)
    }

    @Test func `a torn last line is named with its line number, and the original's fate is stated`() throws {
        let torn = try recorder(header + entry + "{\"id\":\"b")
        #expect(
            torn.repairNotice
                == "The session file had a problem, repaired as it was opened: the last line (line 3) was cut off "
                + "mid-write and was dropped. The original is kept as a .damaged copy once anything is added.")
    }

    @Test func `several problems list the first three and count the rest`() throws {
        let messy = try recorder(header + "garbage\n" + entry + "more garbage\n" + "again\n" + "and again\n")
        let notice = try #require(messy.repairNotice)
        #expect(
            notice.hasPrefix(
                "The session file had 4 problems, repaired as it was opened: line 2 was not a valid record"))
        #expect(notice.contains(", and 1 more."))
    }

    @Test func `every kind of repair has a sentence naming its line`() {
        let id = EntryID("e")
        let issues: [SessionLogIssue] = [
            .missingHeader, .tornFinalLine(line: 7), .unterminatedFinalLine(line: 7), .malformedLine(line: 7),
            .lineTooLong(line: 7), .duplicateEntry(id, line: 7), .invalidIdentifier(id, line: 7),
            .orphanedEntry(id, missingParent: id, line: 7), .droppedCompaction(id, boundary: id, line: 7),
            .ignoredLeaf(id, line: 7)
        ]
        for issue in issues {
            if case .missingHeader = issue { continue }
            #expect(issue.explanation.contains("line 7"), "\(issue)")
        }
        #expect(Set(issues.map(\.explanation)).count == issues.count, "each kind says something different")
    }
}
