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

/// The session `ask -p` records into: the resumed one, else a new one, routed to the run's model, with the run's sandbox.
private func promptSession(
    resumed: SessionRecorder?,
    in directory: SessionDirectory,
    model: ResolvedModel,
    source: ConfigurationSource,
    settings: RunSettings
) -> SessionRecorder {
    let session: SessionRecorder
    if let resumed {
        session = resumed
    } else {
        do {
            try directory.create()
            let protection = SessionKeyAccess.protection
            session = SessionRecorder(
                try SessionFile.create(
                    at: FilePath(directory.newSessionPath()),
                    format: protection.format,
                    keyring: protection.keyring
                )
            )
        } catch {
            fail("ask: cannot create a session: \(error)", code: 73)
        }
    }
    if let notice = SessionTasks.follow(session, scope: settings.configuration.taskScope.value) { say([notice]) }
    do {
        try session.select(
            SessionRouting.destination(model),
            explicitlySelected: source.flags.provider != nil || source.flags.selected != nil
        )
    } catch { fail("ask: \(error)", code: 78) }
    do { try settings.record(in: session) } catch {
        fail("ask: cannot record the session's sandbox: \(error)", code: 73)
    }
    return session
}

/// Runs `prompt` to completion. SIGINT and SIGTERM abort the run, so a running command's whole process group
/// is stopped, and then exit with 128 + the signal.
func runPrompt(
    _ prompt: String,
    source: ConfigurationSource,
    settings: RunSettings,
    resumed: SessionRecorder?,
    startupNotices: [String],
    json: Bool = false
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
    // With --json the events go to standard output as JSON lines instead (roadmap 0234); the renderer still counts the tokens.
    let renderer = json ? PrintRenderer(out: { _ in }, err: { _ in }) : PrintRenderer()
    let events = json ? JSONEvents() : nil
    let show: @Sendable (AgentEvent) -> Void = { event in
        renderer.render(event)
        events?.write(event)
    }
    let loop: AgentLoop
    let mcp = startMCPServers(settings, jobs: jobs)
    do {
        await waitForMCPServers(mcp)
        loop = try makeLoop(
            settings,
            instructions: files,
            jobs: jobs,
            transport: transport,
            live: mcp.live,
            reportEvent: show
        )
    } catch {
        fail("ask: \(error)", code: 70)
    }
    let session = promptSession(resumed: resumed, in: directory, model: model, source: source, settings: settings)
    let sessionPath = session.path

    let sent = SessionTasks.attachReferences(
        expandingSkill(prompt, settings: settings, workingDirectory: workingDirectory)
    )
    // Awake for the run and for any job it leaves running until ask stops them below (roadmap 0090).
    let keepAwake = awake(settings)
    defer { keepAwake.turnEnded() }
    let run = Task<Void, any Error> {
        // Each @server:uri read from its server, which has connected above (roadmap 0067).
        // Then each #123 it names, from the workspace's GitHub repository (roadmap 0186).
        let attached = await ForgeAttachment.attach(await mcp.attachResources(sent), workspace: settings.workspace)
        try await loop.run(attached, in: session, events: show)
    }
    let interrupted = Mutex<Int32?>(nil)
    let signals = SignalHandler(
        onResize: {},
        onShutdown: { signal in
            interrupted.withLock { $0 = signal }
            run.cancel()
        }
    )
    try? signals.start()
    let result = await run.result
    // Jobs outlive turns, not ask: whatever ended the run, nothing it started keeps running.
    await jobs.stopAll()
    await mcp.stop()
    signals.stop()
    events?.end(session: sessionPath)
    FileHandle.standardError.write(Data("ask: tokens \(renderer.usageSummary)\nask: session \(sessionPath)\n".utf8))
    if let signal = interrupted.withLock({ $0 }) { Foundation.exit(128 + signal) }
    if case .failure(let error) = result { fail("ask: \(error)", code: 69) }
}

/// The Mac kept awake as `settings` say, already holding for the run that is about to start.
private func awake(_ settings: RunSettings) -> KeepAwake {
    let keepAwake = KeepAwake(
        mode: settings.configuration.keepAwake.value,
        display: settings.configuration.keepDisplayAwake.value
    )
    keepAwake.turnStarted()
    return keepAwake
}
