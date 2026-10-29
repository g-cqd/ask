internal import Foundation
internal import System
internal import Testing

@testable import AskAgentCore

/// Opening a session reads its file a chunk at a time (roadmap 0088 step 3): whatever the chunk size, the session and its repairs are what
/// reading the file whole gave.
@Suite("A session read in chunks is the session read whole")
struct SessionLogReaderTests {
    private static let header = #"{"type":"session","version":2}"#

    private static func entry(_ id: Int, parent: Int?, text: String) -> String {
        let parentField = parent.map { #""parent":"\#($0)","# } ?? ""
        return #"{"id":"\#(id)",\#(parentField)"payload":{"kind":"user","text":"\#(text)"},"type":"entry"}"#
    }

    /// A log with the damage recovery repairs: corrupt and empty lines, a line past the limit, a missing parent, a leaf record, and
    /// optionally a torn or unterminated last line.
    private static func damagedLog(seed: UInt64) -> [UInt8] {
        var random = SeededGenerator(seed: seed)
        var lines = [header]
        for id in 0 ..< Int.random(in: 1 ... 40, using: &random) {
            let text = String(repeating: "word ", count: Int.random(in: 0 ... 60, using: &random))
            switch Int.random(in: 0 ..< 12, using: &random) {
                case 0: lines.append("{garbage")
                case 1: lines.append("")
                case 2: lines.append(entry(id, parent: id > 0 ? id - 1 : nil, text: String(repeating: "x", count: 300)))
                case 3: lines.append(entry(id, parent: id + 1000, text: text))
                case 4 where id > 0: lines.append(#"{"id":"\#(id - 1)","type":"leaf"}"#)
                default: lines.append(entry(id, parent: id > 0 ? id - 1 : nil, text: text))
            }
        }
        var text = lines.joined(separator: "\n")
        switch Int.random(in: 0 ..< 3, using: &random) {
            case 0: text += "\n"
            case 1: text += "\n" + #"{"id":"torn","pa"#
            default: break
        }
        return Array(text.utf8)
    }

    private static let limits = SessionLog.Limits(maximumLineBytes: 256, maximumArchiveBytes: 1 << 20)

    private static func recoverInChunks(_ bytes: [UInt8], chunk: Int) throws -> RecoveredSession {
        var lines = SessionLogReader.Lines(
            recovery: SessionLogRecovery(limits: limits, images: nil), limit: limits.maximumLineBytes)
        var start = 0
        while start < bytes.count {
            let end = Swift.min(bytes.count, start + chunk)
            try lines.feed(bytes[start ..< end])
            start = end
        }
        try lines.finish()
        return lines.recovery.result
    }

    @Test(arguments: 0 ..< 60)
    func `every chunk size recovers what the whole file recovers`(seed: Int) throws {
        let bytes = Self.damagedLog(seed: UInt64(seed))
        let whole = try SessionLog.recover(bytes, limits: Self.limits)
        for chunk in [1, 2, 3, 7, 64, 255, 256, 257, 4096] {
            #expect(try Self.recoverInChunks(bytes, chunk: chunk) == whole, "seed \(seed), chunk \(chunk)")
        }
    }

    @Test func `a file is read through the descriptor in chunks, and an empty one has no header`() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "ask-reader-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for (name, bytes) in [("log", Self.damagedLog(seed: 7)), ("empty", [])] {
            let path = directory.appending(path: name).path
            FileManager.default.createFile(atPath: path, contents: Data(bytes))
            let descriptor = try FileDescriptor.open(FilePath(path), .readOnly)
            defer { try? descriptor.close() }
            let read = try SessionLogReader(chunkBytes: 5).recover(descriptor, limits: Self.limits, images: nil)
            #expect(read == (try SessionLog.recover(bytes, limits: Self.limits)))
        }
    }
}
