/// The interactive screen's conversation: each prompt is a run of the agent loop in one session.

internal import AskAI
internal import AskAgentCore
internal import AskTUI
internal import Foundation
internal import Synchronization
internal import System

/// Runs prompts through the agent loop, recording them in one session.
///
/// The loop and the session are both made on the first prompt, not at launch: nothing needs them before then,
/// and building the loop measured about 1.2 ms of cold start.
final class AgentConversation: Conversation {
    private let makeLoop: @Sendable () throws -> AgentLoop
    private let directory: SessionDirectory
    private let loop = Mutex<AgentLoop?>(nil)
    private let session = Mutex<SessionRecorder?>(nil)

    init(directory: SessionDirectory, makeLoop: @escaping @Sendable () throws -> AgentLoop) {
        self.makeLoop = makeLoop
        self.directory = directory
    }

    func start(_ prompt: String, update: @escaping @Sendable (ConversationUpdate) -> Void) -> Task<Void, Never> {
        Task {
            do {
                let loop = try self.agentLoop()
                let recorder = try self.recorder()
                try await loop.run(prompt, in: recorder) { event in
                    if let shown = Self.update(for: event) { update(shown) }
                }
            } catch AgentError.cancelled {
                update(.notice("Aborted. Results already known were kept.", isError: false))
            } catch {
                update(.notice("ask: \(error)", isError: true))
            }
            update(.runEnded)
        }
    }

    private func agentLoop() throws -> AgentLoop {
        try loop.withLock { existing throws -> AgentLoop in
            if let existing { return existing }
            let created = try makeLoop()
            existing = created
            return created
        }
    }

    /// The session, created on the first prompt so that opening and closing ask leaves no empty sessions.
    private func recorder() throws -> SessionRecorder {
        try session.withLock { existing throws -> SessionRecorder in
            if let existing { return existing }
            try FileManager.default.createDirectory(atPath: directory.path, withIntermediateDirectories: true)
            let created = SessionRecorder(try SessionFile.create(at: FilePath(directory.newSessionPath())))
            existing = created
            return created
        }
    }

    private static func update(for event: AgentEvent) -> ConversationUpdate? {
        switch event {
            case .model(.textDelta(_, let text)): return .assistantText(text)
            case .toolStarted(_, let name, let input):
                return .toolStarted(name: name, summary: toolSummary(name: name, input: input))
            case .toolFinished(_, _, let output):
                let last = output.content.split(separator: "\n").last.map(String.init) ?? ""
                return .toolFinished(output.isError ? .failed(last) : .succeeded)
            case .repaired(let repairs):
                return .notice("Repaired the context before this turn: \(repairs)", isError: false)
            case .retrying(let attempt, let total, let delay, let reason):
                return .notice(retryNotice(attempt: attempt, of: total, delay: delay, reason: reason), isError: false)
            default: return nil
        }
    }
}

/// The interactive screen in the working directory.
func runInteractive(model: String) async {
    let workingDirectory = FileManager.default.currentDirectoryPath
    do {
        let files = instructionFiles(workingDirectory: workingDirectory)
        let conversation = AgentConversation(directory: SessionDirectory(project: workingDirectory)) {
            try makeLoop(
                model: model, workingDirectory: workingDirectory, instructions: files, transport: URLSessionTransport())
        }
        try await runInteractiveScreen(conversation: conversation, label: model, notices: describe(files))
    } catch {
        // The screen has already restored the terminal by the time an error reaches here.
        fail("ask: \(error)", code: 70)
    }
}
