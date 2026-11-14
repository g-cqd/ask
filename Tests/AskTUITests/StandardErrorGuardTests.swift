internal import Foundation
internal import Testing

@testable import AskTUI

/// While the screen is open, what the process writes to standard error goes to a file, not to the terminal the screen is drawn on
/// (the owner, 2026-11-14: a system library's database errors were printed over the screen). Tested on a pipe standing for standard
/// error, so the test's own is left alone.
@Suite("Standard error is kept off the screen")
struct StandardErrorGuardTests {
    private func pipeEnds() throws -> (read: Int32, write: Int32) {
        var ends: [Int32] = [0, 0]
        try #require(pipe(&ends) == 0)
        return (ends[0], ends[1])
    }

    private func write(_ text: String, to descriptor: Int32) {
        _ = text.withCString { Darwin.write(descriptor, $0, strlen($0)) }
    }

    /// What can be read from `descriptor` now, without waiting.
    private func available(_ descriptor: Int32) -> String {
        _ = fcntl(descriptor, F_SETFL, O_NONBLOCK)
        var buffer = [UInt8](repeating: 0, count: 4096)
        let count = read(descriptor, &buffer, buffer.count)
        return count > 0 ? String(decoding: buffer[..<count], as: UTF8.self) : ""
    }

    @Test func `what is written while guarded goes to the log, and afterwards to where it went before`() throws {
        let (reader, writer) = try pipeEnds()
        defer {
            close(reader)
            close(writer)
        }
        let log = FileManager.default.temporaryDirectory
            .appendingPathComponent("ask-stderr-\(UUID().uuidString)/stderr.log").path
        defer { try? FileManager.default.removeItem(atPath: (log as NSString).deletingLastPathComponent) }

        write("before\n", to: writer)
        let quiet = try #require(StandardErrorGuard(logPath: log, descriptor: writer))
        write("a library's error\n", to: writer)
        let written = quiet.end()
        write("after\n", to: writer)

        #expect(available(reader) == "before\nafter\n", "nothing written while guarded reached the terminal's side")
        let kept = try String(contentsOfFile: log, encoding: .utf8)
        #expect(kept.hasSuffix("a library's error\n") && kept.contains("--- ask "))
        #expect(written == "a library's error\n".utf8.count)
        let mode = try FileManager.default.attributesOfItem(atPath: log)[.posixPermissions] as? Int
        #expect(mode == 0o600)
        #expect(quiet.end() == 0, "ending twice restores nothing twice")
    }

    @Test func `a log that cannot be opened guards nothing and breaks nothing`() throws {
        let (reader, writer) = try pipeEnds()
        defer {
            close(reader)
            close(writer)
        }
        #expect(StandardErrorGuard(logPath: "/dev/null/nowhere/stderr.log", descriptor: writer) == nil)
        write("still there\n", to: writer)
        #expect(available(reader) == "still there\n")
    }

    @Test func `a log past its size starts again, so it never grows without end`() throws {
        let (reader, writer) = try pipeEnds()
        defer {
            close(reader)
            close(writer)
        }
        let log = FileManager.default.temporaryDirectory
            .appendingPathComponent("ask-stderr-\(UUID().uuidString)/stderr.log").path
        defer { try? FileManager.default.removeItem(atPath: (log as NSString).deletingLastPathComponent) }
        try FileManager.default.createDirectory(
            atPath: (log as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true
        )
        try Data(repeating: 0x78, count: StandardErrorGuard.maximumLogBytes + 1).write(to: URL(fileURLWithPath: log))
        let quiet = try #require(StandardErrorGuard(logPath: log, descriptor: writer))
        _ = quiet.end()
        let size = try FileManager.default.attributesOfItem(atPath: log)[.size] as? Int
        #expect((size ?? .max) < 200)
    }
}
