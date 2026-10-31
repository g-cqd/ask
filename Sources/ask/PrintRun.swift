/// `ask -p`: one prompt, run by the agent loop with the tools, recorded as a session. Binding only: the
/// behaviour is in AskAgentCore, AskAI and AskTools.

internal import AskAI
internal import AskAgentCore
internal import AskTools
internal import Foundation
internal import Synchronization
internal import System
internal import TerminalKitInput

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

/// Says `lines` on standard error, which stays free of the answer.
private func say(_ lines: [String]) {
    for line in lines { FileHandle.standardError.write(Data("ask: \(line)\n".utf8)) }
}

/// Runs `prompt` to completion. SIGINT and SIGTERM abort the run, so a running command's whole process group
/// is stopped, and then exit with 128 + the signal.
func runPrompt(
    _ prompt: String, source: ConfigurationSource, settings: RunSettings, resumed: SessionRecorder?,
    startupNotices: [String]
)
    async
{
    let workingDirectory = FileManager.default.currentDirectoryPath
    let directory = SessionDirectory(project: workingDirectory, environment: LaunchEnvironment.values)
    let model = settings.model
    say(startupNotices + settings.description)
    // Before anything can refuse the run: what ask decided is most useful when it then stops (a signed-out connection).
    let files = instructionFiles(workingDirectory: workingDirectory)
    if settings.verbose { say(settings.detailLines + ProjectInstructions.describe(files)) }
    let transport = URLSessionTransport()
    await requireSignIn(for: model, transport: transport)
    let jobs = JobTable(environment: LaunchEnvironment.values)
    let loop: AgentLoop
    let mcp = startMCPServers(settings, jobs: jobs)
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
            try directory.create()
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
    // Awake for the run and for any job it leaves running until ask stops them below (roadmap 0090).
    let keepAwake = awake(settings)
    defer { keepAwake.turnEnded() }
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

/// The Mac kept awake as `settings` say, already holding for the run that is about to start.
private func awake(_ settings: RunSettings) -> KeepAwake {
    let keepAwake = KeepAwake(
        mode: settings.configuration.keepAwake.value, display: settings.configuration.keepDisplayAwake.value)
    keepAwake.turnStarted()
    return keepAwake
}
