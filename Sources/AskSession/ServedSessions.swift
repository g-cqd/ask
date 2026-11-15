internal import AskAI
internal import AskAgentCore
package import AskTUI
internal import AskTools
internal import Foundation
internal import Synchronization

/// The conversations `ask serve` holds (ADR-0154): one for each session a client asks for, made for the client's folder as the
/// screen's is made for the launch's, and what each leaves running until ask exits.
///
/// Nothing here knows the protocol a client speaks: it makes conversations, which the screen's `Conversation` seam drives.
package final class ServedSessions: Sendable {
    /// A served conversation and the name of its session: its session file's, so the session can be found again by it.
    package struct Made: Sendable {
        package let id: String
        package let conversation: any Conversation
    }

    /// Why no conversation could be made for a folder.
    package struct NotAFolder: Error, CustomStringConvertible {
        let path: String
        package var description: String { "\(path) is not a folder ask can work in" }
    }

    private struct Held {
        let conversation: AgentConversation
        let jobs: JobTable
        let mcp: MCPHub
    }

    private let environment: [String: String]
    private let flags: ConfigurationSource.Flags
    private let allowNetwork: Bool
    private let held = Mutex<[Held]>([])
    /// How sessions are kept is decided once, with the first session's configuration, as a launch decides it; a test leaves it.
    private let decidesProtection: Bool
    private let protection = Mutex<Task<Void, Never>?>(nil)

    /// Sessions made in the process's environment, with the configuration's own choice of a model.
    package convenience init() {
        self.init(environment: LaunchEnvironment.values, flags: ConfigurationSource.Flags(), allowNetwork: true)
    }

    init(
        environment: [String: String],
        flags: ConfigurationSource.Flags,
        allowNetwork: Bool,
        decidesProtection: Bool = true
    ) {
        self.environment = environment
        self.flags = flags
        self.allowNetwork = allowNetwork
        self.decidesProtection = decidesProtection
    }

    /// A conversation for `folder`, which is read as the kernel would (links followed), and must be one.
    /// - Throws: ``NotAFolder``, or why the folder's configuration gives no run (no model, a file that does not parse).
    package func make(in folder: String) async throws -> Made {
        var isDirectory: ObjCBool = false
        guard let workspace = CanonicalPath.of(folder, relativeTo: "/"),
            FileManager.default.fileExists(atPath: workspace, isDirectory: &isDirectory), isDirectory.boolValue
        else { throw NotAFolder(path: folder) }
        let source = ConfigurationSource(workingDirectory: workspace, flags: flags, environment: environment)
        let settings = try await source.load(allowNetwork: allowNetwork)
        await decideProtection(settings.configuration)
        let jobs = JobTable(environment: environment)
        // Connected on a session's first message, as the screen's are (roadmap 0143).
        let mcp = startMCPServers(settings, jobs: jobs, connectsOnFirstNeed: true, environment: environment)
        let conversation = AgentConversation(
            directory: SessionDirectory(project: workspace, environment: environment),
            settings: settings,
            source: source,
            jobs: jobs,
            mcp: mcp,
            makeLoop: conversationLoop(
                instructions: instructionFiles(workingDirectory: workspace),
                jobs: jobs,
                mcp: mcp
            )
        )
        held.withLock { $0.append(Held(conversation: conversation, jobs: jobs, mcp: mcp)) }
        let file = (conversation.plannedSessionPath() as NSString).lastPathComponent
        return Made(id: (file as NSString).deletingPathExtension, conversation: conversation)
    }

    /// Stops what the sessions left running: their threads, their jobs, their MCP servers.
    package func stopAll() async {
        for session in held.withLock({ $0 }) {
            await session.conversation.stopThreads()
            await session.jobs.stopAll()
            await session.mcp.stop()
        }
    }

    private func decideProtection(_ configuration: Configuration) async {
        guard decidesProtection else { return }
        let deciding = protection.withLock { task -> Task<Void, Never> in
            if let task { return task }
            let made = Task { await SessionProtectionSetup.decideAtLaunch(configuration, inScreen: false) }
            task = made
            return made
        }
        await deciding.value
    }
}
