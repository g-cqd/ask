import Foundation
import System
import Testing

@testable import AskAgentCore

/// Each entry carries when it was recorded (roadmap 0239), what a turn's and a task's time are read from: written with the entry, kept
/// across a reopen, a fork and a rewrite, absent from what an older ask wrote, and read past by an ask that does not know the key.
@Suite("An entry carries when it was recorded")
struct SessionEntryTimeTests {
    private let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "ask-time-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func path(_ name: String) -> FilePath { FilePath(directory.appending(path: name).path) }

    private static func milliseconds() -> Int { Int(Date().timeIntervalSince1970 * 1_000) }

    @Test func `an appended entry has the time it was recorded, kept when the session is opened again and forked`()
        throws
    {
        defer { try? FileManager.default.removeItem(at: directory) }
        let before = Self.milliseconds()
        do {
            var file = try SessionFile.create(at: path("s.jsonl"))
            try file.append(.user("one"))
            try file.append(.assistant("two"))
        }
        let after = Self.milliseconds()
        let reopened = try SessionFile.open(at: path("s.jsonl"))
        let times = reopened.tree.entries.map(\.recordedAt)
        #expect(times.count == 2)
        #expect(
            times.allSatisfy { ($0 ?? 0) >= before - 1 && ($0 ?? .max) <= after + 1 },
            "\(times) not in \(before)...\(after)"
        )
        let fork = try reopened.fork(upTo: reopened.tree.leaf, to: path("f.jsonl"))
        #expect(fork.tree.entries.map(\.recordedAt) == times)
        #expect(
            try SessionLog.recover(SessionLog.snapshot(reopened.tree)).tree.entries.map(\.recordedAt) == times,
            "a rewrite"
        )
    }

    @Test func `a line an older ask wrote has no time, and a line with a key this ask does not know still loads`()
        throws
    {
        let lines = [
            #"{"type":"session","version":2}"#,
            #"{"id":"a","payload":{"kind":"user","text":"x"},"type":"entry"}"#,
            #"{"id":"b","parent":"a","payload":{"kind":"assistant","text":"y"},"time":1763800000000,"type":"entry"}"#,
            // What an older ask meets in a line this one writes: a key of the entry record it does not have.
            #"{"id":"c","later":7,"parent":"b","payload":{"kind":"user","text":"z"},"type":"entry"}"#
        ]
        let recovered = try SessionLog.recover(Array((lines.joined(separator: "\n") + "\n").utf8))
        #expect(recovered.issues.isEmpty)
        #expect(recovered.tree.entries.map(\.recordedAt) == [nil, 1_763_800_000_000, nil])
    }
}
