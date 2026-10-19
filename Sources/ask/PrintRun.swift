/// `ask -p`: one prompt, run by the agent loop with the tools, recorded as a session. Binding only: the
/// behaviour is in AskAgentCore, AskAI and AskTools.

internal import AskAI
internal import AskAgentCore
internal import AskTools
internal import Foundation
internal import Synchronization
internal import System
internal import TerminalKitInput

/// The answer goes to standard output; tool activity and diagnostics to standard error.
private final class PrintRenderer: Sendable {
    private let midLine = Mutex(false)
    private let usage = Mutex(UsageTotals())

    /// Token usage over the run, for the closing line.
    var usageSummary: String { usage.withLock { $0.summary } }

    func render(_ event: AgentEvent) {
        if let spent = event.usage { usage.withLock { $0.add(spent) } }
        if let notice = compactionNotice(event) {
            endLine()
            write("ask: \(notice)\n", to: .standardError)
        }
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
            case .continuedAtOutputLimit:
                endLine()
                write("ask: the response hit the output limit; asking the model to continue.\n", to: .standardError)
            case .retrying(let attempt, let total, let delay, let reason):
                endLine()
                write(
                    "ask: \(retryNotice(attempt: attempt, of: total, delay: delay, reason: reason))\n",
                    to: .standardError)
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
func runPrompt(_ prompt: String, source: ConfigurationSource, settings: RunSettings, session choice: SessionChoice)
    async
{
    let model = settings.model
    for line in settings.description { FileHandle.standardError.write(Data("ask: \(line)\n".utf8)) }
    let transport = URLSessionTransport()
    await requireSignIn(for: model.provider, transport: transport)
    let workingDirectory = FileManager.default.currentDirectoryPath
    let jobs = JobTable()
    let loop: AgentLoop
    let files = instructionFiles(workingDirectory: workingDirectory)
    for line in describe(files) { FileHandle.standardError.write(Data("ask: \(line)\n".utf8)) }
    do {
        loop = try makeLoop(
            settings, workingDirectory: workingDirectory, instructions: files, jobs: jobs, transport: transport)
    } catch {
        fail("ask: \(error)", code: 70)
    }
    let directory = SessionDirectory(project: workingDirectory)
    let session: SessionRecorder
    if let resumed = choice.open(in: directory, note: { FileHandle.standardError.write(Data("ask: \($0)\n".utf8)) }) {
        session = resumed
    } else {
        do {
            try FileManager.default.createDirectory(atPath: directory.path, withIntermediateDirectories: true)
            session = SessionRecorder(try SessionFile.create(at: FilePath(directory.newSessionPath())))
        } catch {
            fail("ask: cannot create a session: \(error)", code: 73)
        }
    }
    let sessionPath = session.path
    let renderer = PrintRenderer()

    let run = Task<Void, any Error> {
        try await loop.run(prompt, in: session) { renderer.render($0) }
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
    // Jobs outlive turns, not ask: whatever ended the run, nothing it started keeps running.
    await jobs.stopAll()
    signals.stop()
    FileHandle.standardError.write(Data("ask: tokens \(renderer.usageSummary)\nask: session \(sessionPath)\n".utf8))
    if let signal = interrupted.withLock({ $0 }) { Foundation.exit(128 + signal) }
    if case .failure(let error) = result { fail("ask: \(error)", code: 69) }
}
