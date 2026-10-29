import Foundation
import Testing

@testable import AskTools

/// Against real files. No sleeps: every wait ends on a signal, and the time limit fails a test whose signal never comes.
@Suite("Configuration files changing raise one signal per save", .timeLimit(.minutes(1)))
struct FileChangeSignalTests {
    private let directory: String

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "ask-signal-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    }

    @Test func `an atomic save, a write in place and a file made under a missing directory each signal`() async throws {
        let user = directory + "/config.json"
        let project = directory + "/project/.ask/config.json"
        try Data("{}".utf8).write(to: URL(filePath: user))
        var signals = FileChangeSignal.changes(of: [user, project], quiet: .milliseconds(20)).makeAsyncIterator()

        // Noise beside a watched file is not a change to it: the first report names the save alone.
        try Data("noise".utf8).write(to: URL(filePath: directory + "/other.log"))
        try Data("{\"maxTurns\": 3}".utf8).write(to: URL(filePath: user), options: .atomic)
        #expect(await signals.next() == [user], "atomic save")

        let handle = try #require(FileHandle(forWritingAtPath: user))
        try handle.write(contentsOf: Data("{\"maxTurns\": 4}".utf8))
        try handle.close()
        #expect(await signals.next() == [user], "write in place")

        try FileManager.default.createDirectory(atPath: directory + "/project/.ask", withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: URL(filePath: project))
        #expect(await signals.next() == [project], "created under a missing directory")
        try? FileManager.default.removeItem(atPath: directory)
    }
}
