import Darwin
import Foundation
import Synchronization
import Testing

@testable import AskAgentCore

/// The trust store is replaced by renaming a new file over it, and was flushed not at all (roadmap 0060, ADR-0089): a crash could leave an
/// empty trust file, which reads as "nothing is trusted" and costs the user a repeated `ask trust`, or a file that is not what they saw.
@Suite("The trust store is made durable before its rename and its directory after it")
struct ProjectTrustDurabilityTests {
    /// The flushes a test saw, in order.
    private final class Events: Sendable {
        private let log = Mutex<[String]>([])
        func add(_ event: String) { log.withLock { $0.append(event) } }
        var all: [String] { log.withLock { $0 } }
    }

    private let directory: URL
    private var path: String { directory.appending(path: "trust.json").path }

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "ask-trust-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func recording(_ events: Events, failing: String? = nil) -> (Int32) -> Int32 {
        let path = path
        return { descriptor in
            var info = stat()
            fstat(descriptor, &info)
            let kind = info.st_mode & S_IFMT == S_IFDIR ? "directory" : "file"
            events.add("\(kind) while \(FileManager.default.fileExists(atPath: path) ? "present" : "absent")")
            if kind == failing {
                errno = EIO
                return -1
            }
            return 0
        }
    }

    @Test func `the bytes are flushed before the rename and the directory after it`() throws {
        let events = Events()
        try ProjectTrust().save(to: path, flush: recording(events))
        #expect(events.all == ["file while absent", "directory while present"])
        #expect(try ProjectTrust.load(path) == ProjectTrust())
    }

    @Test func `a flush that fails is reported, and leaves no store and no temporary file`() throws {
        let events = Events()
        #expect(throws: ConfigurationError.self) {
            try ProjectTrust().save(to: path, flush: recording(events, failing: "file"))
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }
}
