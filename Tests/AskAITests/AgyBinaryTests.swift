internal import Foundation
internal import Testing

@testable import AskAI

/// Where `agy` is installed. Probed on this machine: `/opt/homebrew/bin/agy`, a plain file updated in place by `agy update`.
struct AgyBinaryTests {
    private func locate(_ environment: [String: String], existing: Set<String>, home: String = "/home/u") -> String? {
        AgyBinary.locate(environment: environment, home: home) { existing.contains($0) }
    }

    @Test func `an explicit override wins, even over a binary on the path`() {
        let found = locate(["AGY_BINARY": "/custom/agy", "PATH": "/bin"], existing: ["/bin/agy"])
        #expect(found == "/custom/agy")
    }

    @Test func `an empty override is no override`() {
        #expect(locate(["AGY_BINARY": "  ", "PATH": "/bin"], existing: ["/bin/agy"]) == "/bin/agy")
    }

    @Test func `the path is searched in order, agy before its original name`() {
        #expect(locate(["PATH": "/a:/b"], existing: ["/a/antigravity", "/b/agy"]) == "/b/agy")
        #expect(locate(["PATH": "/a:/b"], existing: ["/a/agy", "/b/agy"]) == "/a/agy")
        #expect(locate(["PATH": "/a:/b"], existing: ["/b/antigravity"]) == "/b/antigravity")
    }

    @Test func `empty path entries are skipped, not taken for the working directory`() {
        #expect(locate(["PATH": ":/a"], existing: ["/agy", "agy"]) == nil, "an empty entry must not become the root")
    }

    @Test func `known install places are tried when the path is empty, as for a program started without a shell`() {
        #expect(locate([:], existing: ["/opt/homebrew/bin/agy"]) == "/opt/homebrew/bin/agy")
        #expect(locate([:], existing: ["/home/u/.local/bin/agy"], home: "/home/u") == "/home/u/.local/bin/agy")
        #expect(locate([:], existing: ["/usr/local/bin/antigravity"]) == "/usr/local/bin/antigravity")
    }

    @Test func `nothing installed is nil, not a guess`() {
        #expect(locate(["PATH": "/a"], existing: []) == nil)
    }
}
