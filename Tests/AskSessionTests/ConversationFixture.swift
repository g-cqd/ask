internal import AskAI
internal import AskAgentCore
internal import AskTUI
internal import AskTools
internal import Foundation
internal import Synchronization
internal import System

@testable import AskSession

/// A conversation over a temporary home and project, with no network: its settings come from a key in its own environment, its loop is
/// never made, and what it tells the screen is kept.
final class ConversationFixture: Sendable {
    let root: URL
    let directory: SessionDirectory
    let conversation: AgentConversation
    private let seen = Mutex<[ConversationUpdate]>([])

    var updates: [ConversationUpdate] { seen.withLock { $0 } }
    var update: @Sendable (ConversationUpdate) -> Void { { [self] update in self.seen.withLock { $0.append(update) } } }

    init() async throws {
        root = FileManager.default.temporaryDirectory.appending(path: "ask-session-\(UUID().uuidString)")
        let project = root.appending(path: "project").path
        try FileManager.default.createDirectory(atPath: project, withIntermediateDirectories: true)
        let environment = ["HOME": root.path, "ANTHROPIC_API_KEY": "test-key", "PATH": "/usr/bin:/bin"]
        let source = ConfigurationSource(
            workingDirectory: project,
            flags: .init(model: "claude-test-1", provider: "anthropic"),
            environment: environment
        )
        let settings = try await source.load(allowNetwork: false)
        directory = SessionDirectory(project: project, environment: environment)
        let jobs = JobTable(environment: environment)
        conversation = AgentConversation(
            directory: directory,
            settings: settings,
            source: source,
            jobs: jobs,
            mcp: MCPHub(
                environment: environment,
                transport: MCPHub.standardTransport(inheriting: environment, jobs: jobs)
            ),
            makeLoop: { _, _ in throw CancellationError() }
        )
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    /// A new session file in the fixture's directory, open for writing.
    func newSession() throws -> SessionRecorder {
        try directory.create()
        let path = directory.newSessionPath(now: Date(timeIntervalSince1970: seconds()))
        return SessionRecorder(try SessionFile.create(at: FilePath(path)))
    }

    private let counter = Mutex(1_700_000_000.0)
    private func seconds() -> Double {
        counter.withLock { value in
            value += 1
            return value
        }
    }

    /// Whether another process could take the writer lock of the session at `path` now.
    static func isUnlocked(_ path: String) -> Bool {
        let descriptor = open(path, O_RDONLY)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { return false }
        flock(descriptor, LOCK_UN)
        return true
    }
}
