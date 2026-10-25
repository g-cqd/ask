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
            case .model(.notice(let text)):
                endLine()
                write("ask: \(text)\n", to: .standardError)
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

/// `prompt`, or for `/skill:name request` the request with the skill after it. A skill that cannot be loaded ends the run with exit code 64 and
/// says why, before anything is sent.
private func expandingSkill(_ prompt: String, settings: RunSettings, workingDirectory: String) -> String {
    guard SkillInvocation.asksForSkill(prompt) else { return prompt }
    let book = SkillBook(settings.configuration.skills.value, workingDirectory: workingDirectory)
    switch SkillInvocation.expand(prompt, catalog: book.catalog, knownSources: book.knownSources) {
        case .prompt(let text): return text
        case .notASkill: return prompt
        case .failure(let reason): fail("ask: \(reason)", code: 64)
    }
}

/// Runs `prompt` to completion. SIGINT and SIGTERM abort the run, so a running command's whole process group
/// is stopped, and then exit with 128 + the signal.
func runPrompt(
    _ prompt: String, source: ConfigurationSource, settings: RunSettings, resumed: SessionRecorder?,
    startupNotices: [String]
)
    async
{
    let directory = SessionDirectory(project: FileManager.default.currentDirectoryPath)
    let model = settings.model
    for line in startupNotices + settings.description { FileHandle.standardError.write(Data("ask: \(line)\n".utf8)) }
    let transport = URLSessionTransport()
    await requireSignIn(for: model, transport: transport)
    let workingDirectory = FileManager.default.currentDirectoryPath
    let jobs = JobTable()
    let loop: AgentLoop
    let mcp = startMCPServers(settings, jobs: jobs)
    let files = instructionFiles(workingDirectory: workingDirectory)
    for line in describe(files) { FileHandle.standardError.write(Data("ask: \(line)\n".utf8)) }
    do {
        await waitForMCPServers(mcp)
        loop = try makeLoop(
            settings, instructions: files, jobs: jobs, transport: transport, live: mcp.live)
    } catch {
        fail("ask: \(error)", code: 70)
    }
    let session: SessionRecorder
    if let resumed {
        session = resumed
    } else {
        do {
            try FileManager.default.createDirectory(atPath: directory.path, withIntermediateDirectories: true)
            session = SessionRecorder(try SessionFile.create(at: FilePath(directory.newSessionPath())))
        } catch {
            fail("ask: cannot create a session: \(error)", code: 73)
        }
    }
    do {
        try session.select(
            SessionRouting.destination(model),
            explicitlySelected: source.flags.provider != nil || source.flags.selected != nil)
    } catch { fail("ask: \(error)", code: 78) }
    do { try settings.record(in: session) } catch {
        fail("ask: cannot record the session's sandbox: \(error)", code: 73)
    }
    let sessionPath = session.path
    let renderer = PrintRenderer()

    let sent = expandingSkill(prompt, settings: settings, workingDirectory: workingDirectory)
    let run = Task<Void, any Error> {
        try await loop.run(sent, in: session) { renderer.render($0) }
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
    await mcp.stop()
    signals.stop()
    FileHandle.standardError.write(Data("ask: tokens \(renderer.usageSummary)\nask: session \(sessionPath)\n".utf8))
    if let signal = interrupted.withLock({ $0 }) { Foundation.exit(128 + signal) }
    if case .failure(let error) = result { fail("ask: \(error)", code: 69) }
}
