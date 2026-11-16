internal import AskAI
package import AskAgentCore
package import AskTUI
internal import AskTools
internal import Foundation
internal import Synchronization
internal import System

/// The conversations `ask serve` holds (ADR-0154): one for each session a client asks for, made for the client's folder as the
/// screen's is made for the launch's, and what each leaves running until ask exits.
///
/// Nothing here knows the protocol a client speaks: it makes conversations, which the screen's `Conversation` seam drives.
package final class ServedSessions: Sendable {
    /// A served conversation and the name of its session: its session file's, so the session can be found again by it.
    package struct Made: Sendable {
        package let id: String
        /// The folder the conversation works in: the one asked for, as the kernel names it.
        package let folder: String
        let serving: AgentConversation
        package var conversation: any Conversation { serving }

        /// What it holds now, as the screen would show it again, oldest first.
        package func history() -> [ConversationUpdate] { serving.history() }
    }

    /// A saved session opened again, and what it holds, oldest first.
    package struct Loaded: Sendable {
        package let made: Made
        package let history: [ConversationUpdate]
    }

    /// Why a saved session could not be opened.
    package struct CannotOpen: Error, CustomStringConvertible {
        package let description: String
        init(_ description: String) { self.description = description }
    }

    /// Why no conversation could be made for a folder.
    package struct NotAFolder: Error, CustomStringConvertible {
        let path: String
        package var description: String { "\(path) is not a folder ask can work in" }
    }

    /// What a client asked of a session besides its folder: whether the model's questions can reach a person, and the MCP
    /// servers the session is to have beside the configuration's.
    private struct Asked {
        let asksPerson: Bool
        let servers: [MCPServerSetting]
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

    /// A conversation for `folder`, which is read as the kernel would (links followed), and must be one. `asksPerson`: whether
    /// the model's questions can reach a person; where they cannot, the model is not offered the tool that asks them.
    /// `servers`: MCP servers the client gave the session (``ClientServers``).
    /// - Throws: ``NotAFolder``, or why the folder's configuration gives no run (no model, a file that does not parse).
    package func make(in folder: String, asksPerson: Bool = true, servers: [MCPServerSetting] = []) async throws -> Made
    {
        let workspace = try workspace(folder)
        let asked = Asked(asksPerson: asksPerson, servers: servers)
        let conversation = try await conversation(in: workspace, resumed: nil, asked: asked)
        let file = (conversation.plannedSessionPath() as NSString).lastPathComponent
        return Made(id: (file as NSString).deletingPathExtension, folder: workspace, serving: conversation)
    }

    /// The saved session `id` of `folder`, opened to be continued, with what it holds as the screen would show it again; nil when
    /// the folder has no such session.
    /// - Throws: ``NotAFolder``, ``CannotOpen``, or why the folder's configuration gives no run.
    package func load(
        _ id: String,
        in folder: String,
        asksPerson: Bool = true,
        servers: [MCPServerSetting] = []
    ) async throws -> Loaded? {
        let workspace = try workspace(folder)
        // An id is a session file's name: one that could name anything else (a path, a hidden file) names no session.
        guard Self.isSessionName(id) else { return nil }
        let path = SessionDirectory(project: workspace, environment: environment).path + "/" + id + ".jsonl"
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let recorder: SessionRecorder
        do {
            recorder = SessionRecorder(try SessionFile.open(at: FilePath(path), keyring: SessionKeyAccess.keyring))
        } catch .locked {
            // Its password is asked on a terminal, never through a client (ADR-0154): the keys are opened there, once.
            throw CannotOpen(
                "session \(id) is encrypted and its keys are not open: run `ask --resume \(id)` in a terminal once"
            )
        } catch .inUse {
            throw CannotOpen("session \(id) is open in another ask")
        } catch {
            throw CannotOpen("session \(id) cannot be read: \(error)")
        }
        let asked = Asked(asksPerson: asksPerson, servers: servers)
        let conversation = try await conversation(in: workspace, resumed: recorder, asked: asked)
        let made = Made(id: id, folder: workspace, serving: conversation)
        return Loaded(made: made, history: made.history())
    }

    /// Whether `id` can only be a session file's name in its folder: ASCII letters, digits, `-` and `_`.
    static func isSessionName(_ id: String) -> Bool {
        !id.isEmpty && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }

    private func workspace(_ folder: String) throws -> String {
        var isDirectory: ObjCBool = false
        guard let workspace = CanonicalPath.of(folder, relativeTo: "/"),
            FileManager.default.fileExists(atPath: workspace, isDirectory: &isDirectory), isDirectory.boolValue
        else { throw NotAFolder(path: folder) }
        return workspace
    }

    /// A conversation in `workspace` as a launch makes the screen's: new, or continuing the session `resumed`.
    private func conversation(
        in workspace: String,
        resumed: SessionRecorder?,
        asked: Asked
    ) async throws -> AgentConversation {
        let source = ConfigurationSource(workingDirectory: workspace, flags: flags, environment: environment)
            .resuming(resumed)
        let settings = try await source.load(allowNetwork: allowNetwork)
        await decideProtection(settings.configuration)
        let jobs = JobTable(environment: environment)
        // Connected on a session's first message, as the screen's are (roadmap 0143).
        let mcp = startMCPServers(
            settings,
            jobs: jobs,
            connectsOnFirstNeed: true,
            also: ClientServers.settings(asked.servers, in: workspace),
            environment: environment
        )
        let conversation = AgentConversation(
            directory: SessionDirectory(project: workspace, environment: environment),
            resumed: resumed,
            settings: settings,
            source: source,
            jobs: jobs,
            mcp: mcp,
            makeLoop: conversationLoop(
                instructions: instructionFiles(workingDirectory: workspace),
                jobs: jobs,
                mcp: mcp,
                asksPerson: asked.asksPerson
            )
        )
        held.withLock { $0.append(Held(conversation: conversation, jobs: jobs, mcp: mcp)) }
        return conversation
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
