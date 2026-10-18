/// `ask -p`: one prompt, run by the agent loop with the tools, recorded as a session. Binding only: the
/// behaviour is in AskAgentCore, AskAI and AskTools.

internal import AskAI
internal import AskAgentCore
internal import AskTools
internal import Foundation
internal import Synchronization
internal import System
internal import TerminalKitInput

/// Adapts the Anthropic client to the loop, resolving auth per request so a long run survives a refresh.
private struct ClaudeProvider: ModelProvider {
    let client: AnthropicClient
    let auth: @Sendable () async throws -> AnthropicClient.Auth

    func stream(_ request: ModelRequest) -> AsyncThrowingStream<ModelEvent, any Error> {
        let (client, auth) = (client, auth)
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await event in client.stream(request, auth: try await auth()) { continuation.yield(event) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// The answer goes to standard output; tool activity and diagnostics to standard error.
private final class PrintRenderer: Sendable {
    private let midLine = Mutex(false)

    func render(_ event: AgentEvent) {
        switch event {
            case .model(.textDelta(_, let text)):
                write(text, to: .standardOutput)
                midLine.withLock { $0 = !text.hasSuffix("\n") }
            case .toolStarted(_, let name, let input):
                endLine()
                let shown = String(decoding: input.bytes, as: UTF8.self)
                write("▸ \(name) \(shown.count > 200 ? String(shown.prefix(200)) + "…" : shown)\n", to: .standardError)
            case .toolFinished(_, _, let output):
                let first = output.content.split(separator: "\n").last.map(String.init) ?? ""
                write(output.isError ? "  ✗ \(first)\n" : "  ✓\n", to: .standardError)
            case .repaired(let repairs):
                write("ask: repaired the context: \(repairs)\n", to: .standardError)
            case .finished:
                endLine()
            default:
                break
        }
    }

    private func endLine() {
        if midLine.withLock({ $0 }) { write("\n", to: .standardOutput) }
        midLine.withLock { $0 = false }
    }

    private func write(_ text: String, to handle: FileHandle) { handle.write(Data(text.utf8)) }
}

/// Runs `prompt` to completion. SIGINT and SIGTERM abort the run, so a running command's whole process group
/// is stopped, and then exit with 128 + the signal.
func runPrompt(_ prompt: String, model: String) async {
    let transport = URLSessionTransport()
    let auth: @Sendable () async throws -> AnthropicClient.Auth
    if let key = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !key.isEmpty {
        auth = { .apiKey(key) }
    } else {
        let access = ClaudeAccess(file: .standard(), client: ClaudeAuthClient(transport: transport))
        do {
            _ = try await access.auth(now: Date().timeIntervalSince1970)
        } catch .signedOut {
            fail("ask: not signed in. Run `ask login`, or set ANTHROPIC_API_KEY.", code: 77)
        } catch {
            fail("ask: \(error)", code: 77)
        }
        auth = { try await access.auth(now: Date().timeIntervalSince1970) }
    }
    let workingDirectory = FileManager.default.currentDirectoryPath
    let tools: ToolRegistry
    do { tools = try ToolRegistry(FileTools.all + [BashTool()]) } catch { fail("ask: \(error)", code: 70) }
    let loop = AgentLoop(
        provider: ClaudeProvider(
            client: AnthropicClient(
                transport: transport,
                endpoint: AnthropicClient.endpoint(environment: ProcessInfo.processInfo.environment)),
            auth: auth),
        tools: tools,
        settings: AgentSettings(
            model: model, maximumTokens: 16_384, systemPrompt: [instructions(workingDirectory: workingDirectory)],
            maximumTurns: 100),
        context: ToolContext(workingDirectory: workingDirectory))
    let directory = SessionDirectory(project: workingDirectory)
    let sessionPath = directory.newSessionPath()
    let renderer = PrintRenderer()

    let run = Task<Void, any Error> {
        try FileManager.default.createDirectory(atPath: directory.path, withIntermediateDirectories: true)
        var file = try SessionFile.create(at: FilePath(sessionPath))
        try await loop.run(prompt, in: &file) { renderer.render($0) }
    }
    let interrupted = Mutex<Int32?>(nil)
    let signals = SignalHandler(
        onResize: {},
        onShutdown: { signal in
            interrupted.withLock { $0 = signal }
            run.cancel()
        })
    try? signals.start()
    let result = await run.result
    signals.stop()
    FileHandle.standardError.write(Data("ask: session \(sessionPath)\n".utf8))
    if let signal = interrupted.withLock({ $0 }) { Foundation.exit(128 + signal) }
    if case .failure(let error) = result { fail("ask: \(error)", code: 69) }
}

/// ask's instructions, carried in the first user message (ADR-0007).
private func instructions(workingDirectory: String) -> String {
    """
    You are ask, a coding agent working in a terminal on macOS. The working directory is \(workingDirectory). \
    Use the tools to read, write and edit files and to run bash commands; relative paths resolve against the \
    working directory. Prefer small changes you have verified, by running the build or tests when there are any. \
    Answer concisely, and say plainly what you did not verify.
    """
}
