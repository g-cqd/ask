import AskAgentCore
import AskTUI
import Foundation
import Synchronization
import Testing

@testable import AskSession

/// The conversations `ask serve` makes (ADR-0154): each for the folder its client named, whatever folder the process is in.
@Suite("A served session is a conversation of its own, in the folder asked for")
struct ServedSessionsTests {
    /// Sessions over a temporary home, with a key in their own environment and no network, and two folders to work in.
    private func layout() throws -> (sessions: ServedSessions, root: URL, folders: [String]) {
        let root = FileManager.default.temporaryDirectory.appending(path: "ask-served-\(UUID().uuidString)")
        let folders = try ["one", "two"]
            .map { name -> String in
                let folder = root.appending(path: name).path
                try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
                return try #require(CanonicalPath.of(folder, relativeTo: "/"))
            }
        let environment = [
            "HOME": root.path, "XDG_CONFIG_HOME": root.appending(path: "config").path,
            "XDG_STATE_HOME": root.appending(path: "state").path, "ANTHROPIC_API_KEY": "test-key",
            "PATH": "/usr/bin:/bin"
        ]
        let sessions = ServedSessions(
            environment: environment,
            flags: .init(model: "claude-test-1", provider: "anthropic"),
            allowNetwork: false,
            decidesProtection: false
        )
        return (sessions, root, folders)
    }

    @Test func `each session is made for its folder, with a session file of its own to be`() async throws {
        let (sessions, root, folders) = try layout()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(!folders.contains(FileManager.default.currentDirectoryPath), "the process is in neither")
        let first = try await sessions.make(in: folders[0])
        let second = try await sessions.make(in: folders[1])
        let again = try await sessions.make(in: folders[0])
        let made = try [first, second, again].map { try #require($0.conversation as? AgentConversation) }
        #expect(made.map { $0.current.withLock { $0.settings.workspace } } == [folders[0], folders[1], folders[0]])
        #expect(made[0].directory.path == made[2].directory.path && made[0].directory.path != made[1].directory.path)
        for (session, conversation) in zip([first, second, again], made) {
            let planned = conversation.plannedSessionPath()
            #expect(planned.hasPrefix(conversation.directory.path + "/"))
            #expect(
                session.id + ".jsonl" == (planned as NSString).lastPathComponent,
                "the id is the session file's name"
            )
        }
        #expect(Set([first.id, second.id, again.id]).count == 3)
        #expect(
            made[0].lists !== made[2].lists && made[0].jobs !== made[2].jobs,
            "two sessions of one folder share nothing"
        )
        await sessions.stopAll()
    }

    @Test func `a folder named through a link is the folder it leads to`() async throws {
        let (sessions, root, folders) = try layout()
        defer { try? FileManager.default.removeItem(at: root) }
        let link = root.appending(path: "link").path
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: folders[1])
        let made = try #require(try await sessions.make(in: link + "/../link/.").conversation as? AgentConversation)
        #expect(made.current.withLock { $0.settings.workspace } == folders[1])
        await sessions.stopAll()
    }

    @Test func `what is not a folder makes no session, and says so`() async throws {
        let (sessions, root, folders) = try layout()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = folders[0] + "/file.txt"
        try Data("x".utf8).write(to: URL(fileURLWithPath: file))
        for path in [file, folders[0] + "/missing", "relative/path\0"] {
            await #expect(throws: ServedSessions.NotAFolder.self, "\(path)") { _ = try await sessions.make(in: path) }
        }
        let refused = await #expect(throws: ServedSessions.NotAFolder.self) { _ = try await sessions.make(in: file) }
        #expect(refused?.description == "\(file) is not a folder ask can work in")
    }
}
