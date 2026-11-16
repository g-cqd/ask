import AskAI
import AskTUI
import Foundation
import Synchronization
import System
import Testing

@testable import AskAgentCore
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

    /// A client that shows no form has nobody to put the model's questions to: the model is not offered the tool.
    @Test func `a session whose client cannot be asked offers the model no question tool, and any other does`()
        async throws
    {
        let (sessions, root, folders) = try layout()
        defer { try? FileManager.default.removeItem(at: root) }
        try savedSession("20261115T100000Z-0badcafe", in: folders[1], root: root)
        let loaded = try #require(
            try await sessions.load("20261115T100000Z-0badcafe", in: folders[1], asksPerson: false)
        )
        let made = try await [
            sessions.make(in: folders[0]), sessions.make(in: folders[0], asksPerson: false), loaded.made
        ]
        let offered = try made.map { session -> Bool in
            let conversation = try #require(session.conversation as? AgentConversation)
            let settings = conversation.current.withLock { $0.settings }
            let loop = try conversation.makeLoop(settings, conversation.loopHooks(settings))
            let names = Set(loop.tools.definitions.map(\.name))
            #expect(names.contains("read"), "the other tools are offered either way")
            return names.contains("question")
        }
        #expect(offered == [true, false, false])
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

    /// A saved session of `folder` holding a prompt and its answer, closed again so that it can be opened.
    private func savedSession(_ id: String, in folder: String, root: URL) throws {
        let environment = ["HOME": root.path, "XDG_STATE_HOME": root.appending(path: "state").path]
        let directory = SessionDirectory(project: folder, environment: environment)
        try FileManager.default.createDirectory(atPath: directory.path, withIntermediateDirectories: true)
        let file = try SessionFile.create(
            at: FilePath(directory.path + "/" + id + ".jsonl"),
            format: SessionFormat(compressed: false, encrypted: false)
        )
        let recorder = SessionRecorder(file)
        _ = try recorder.append(.user("What is in the note?"))
        _ = try recorder.append(.assistant("The note says hello."))
    }

    @Test func `a saved session is opened to be continued, with what it holds, oldest first`() async throws {
        let (sessions, root, folders) = try layout()
        defer { try? FileManager.default.removeItem(at: root) }
        try savedSession("20261115T100000Z-0badcafe", in: folders[0], root: root)
        let loaded = try #require(try await sessions.load("20261115T100000Z-0badcafe", in: folders[0]))
        #expect(loaded.made.id == "20261115T100000Z-0badcafe" && loaded.made.folder == folders[0])
        let said = loaded.history.filter { update in
            if case .userPrompt = update { true } else if case .assistantText = update { true } else { false }
        }
        #expect(said == [.userPrompt("What is in the note?"), .assistantText("The note says hello.")])
        let conversation = try #require(loaded.made.conversation as? AgentConversation)
        #expect(conversation.session.withLock { $0?.path }?.hasSuffix("/20261115T100000Z-0badcafe.jsonl") == true)
        // It has one writer: the conversation that holds it.
        await #expect(throws: ServedSessions.CannotOpen.self) {
            _ = try await sessions.load("20261115T100000Z-0badcafe", in: folders[0])
        }
        await sessions.stopAll()
    }

    @Test func `a session the folder does not have, or a name that is not one, is none`() async throws {
        let (sessions, root, folders) = try layout()
        defer { try? FileManager.default.removeItem(at: root) }
        try savedSession("20261115T100000Z-0badcafe", in: folders[0], root: root)
        #expect(try await sessions.load("20261115T100000Z-0badcafe", in: folders[1]) == nil, "another folder's")
        #expect(try await sessions.load("20261115T100000Z-missing0", in: folders[0]) == nil)
        // A name that reaches out of the folder's sessions is no session, whatever file it would find.
        let environment = ["HOME": root.path, "XDG_STATE_HOME": root.appending(path: "state").path]
        let directory = SessionDirectory(project: folders[0], environment: environment).path
        try Data("{}".utf8).write(to: URL(fileURLWithPath: directory + "/../outside.jsonl"))
        for name in [
            "../outside", "../../../../outside", ".", "", "20261115T100000Z-0badcafe.jsonl", "a/b", "a b", "é", "a\0",
            "²"
        ] {
            #expect(try await sessions.load(name, in: folders[0]) == nil, "\(name)")
            #expect(!ServedSessions.isSessionName(name), "\(name)")
        }
        #expect(ServedSessions.isSessionName("20261115T100000Z-0badcafe") && ServedSessions.isSessionName("a_B-9"))
    }
}
