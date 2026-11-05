/// The providers `Composition.swift` builds for each kind of connection, apart from it to keep each file under the
/// 250-line ceiling.

internal import AemiJSON
internal import AskAI
internal import AskAgentCore
internal import AskApple
internal import AskTools
internal import Foundation

/// Claude's provider, which says so once when a refreshed sign-in could not be saved (ADR-0091).
func claudeProvider(_ resolved: ResolvedModel, transport: URLSessionTransport) -> any ModelProvider {
    let authorization = AnthropicAuthorization(
        file: NamedConnections.file(for: resolved.connection),
        connection: resolved.connection,
        transport: transport
    )
    let notice = RotationNotice(provider: "Claude")
    return NoticingProvider(
        base: ClaudeProvider(
            client: AnthropicClient(
                transport: transport,
                endpoint: AnthropicClient.endpoint(
                    environment: resolved.connection == nil ? LaunchEnvironment.values : [:]
                )
            ),
            auth: requestAuth(authorization)
        ),
        notice: { notice.message(unsavedBecause: authorization.unsavedReason) }
    )
}

/// Codex's provider, which says so once when a refreshed sign-in could not be saved (ADR-0091).
func codexProvider(_ resolved: ResolvedModel, transport: URLSessionTransport) -> any ModelProvider {
    let access = CodexAccess(
        file: NamedConnections.file(for: resolved.connection),
        client: CodexAuthClient(transport: transport),
        connection: resolved.connection
    )
    let notice = RotationNotice(provider: "Codex")
    return NoticingProvider(
        base: CodexProvider(access: access, transport: transport, session: UUID().uuidString),
        notice: { notice.message(unsavedBecause: access.unsavedReason) }
    )
}

/// Antigravity's provider, which says so once when a refreshed sign-in could not be saved (ADR-0091).
func agyProvider(transport: URLSessionTransport) -> any ModelProvider {
    let access = makeAgyAccess(transport: transport)
    let notice = RotationNotice(provider: "Antigravity")
    return NoticingProvider(
        base: AgyProvider(access: access, client: AgyClient(transport: transport)),
        notice: { notice.message(unsavedBecause: access.unsavedReason) }
    )
}

/// The check hook for `section`'s `check` (roadmap 0192), or none: its command runs through `tools`' `bash`, in `context`'s sandbox,
/// without asking, since the person configured it, and shows a `check` block while it runs.
func checkHooks(
    _ section: HooksSection,
    tools: ToolRegistry,
    context: ToolContext,
    reportEvent: (@Sendable (AgentEvent) -> Void)? = nil
) -> [any AgentHook] {
    guard let command = section.check, let input = BashTool.checkInput(command: command, seconds: section.checkSeconds)
    else { return [] }
    let unasked = context.withoutCallGate()
    return [
        CheckHook(command: command) {
            let callID = "check-\(UUID().uuidString)"
            reportEvent?(.toolStarted(id: callID, name: "check", input: input))
            let output = await tools.run(name: "bash", input: input, in: unasked.during(call: callID))
            reportEvent?(.toolFinished(id: callID, name: "check", output: output))
            return BashTool.checkOutcome(of: output)
        }
    ]
}

/// The agent loop with the tools, rooted at `workingDirectory`, following `instructions` after ask's own. Jobs
/// live in `jobs`, which the caller stops when ask exits.
func makeLoop(
    _ run: RunSettings,
    instructions files: [ProjectInstructions.File],
    jobs: JobTable,
    transport: URLSessionTransport,
    approve: SandboxApprover? = nil,
    narrowing: SessionNarrowing = SessionNarrowing(),
    live: LiveTools? = nil,
    destructiveApprover: DestructiveApprover? = nil,
    callGate: ToolCallGate? = nil,
    askPerson: PersonQuestion.Asker? = nil,
    progress: ToolProgressReporter? = nil,
    startSubagent: SubagentTask.Starter? = nil,
    reportEvent: (@Sendable (AgentEvent) -> Void)? = nil
) throws -> AgentLoop {
    // The agent tool only where agents.enabled is on and something can start one (roadmap 0063): off, no request carries it.
    let startSubagent = run.configuration.agents.value.isEnabled ? startSubagent : nil
    let workingDirectory = run.workspace
    let resolved = run.model
    let limits = run.limits
    let sandbox = run.sandbox
    let skills = SkillBook(run.configuration.skills.value, workingDirectory: workingDirectory)
    let agent = settings(
        for: resolved,
        workingDirectory: workingDirectory,
        followedBy: (skills.block.map { [$0] } ?? []) + ProjectInstructions.promptBlocks(files),
        limits: limits,
        sandbox: sandbox,
        thinking: run.thinking
    )
    let tools = try ToolRegistry(
        FileTools.all + [
            BashTool(jobs: jobs, commandEnvironment: run.commandEnvironment), JobActionTool(jobs: jobs),
            NarrowSandboxTool(jobs: jobs), TasksTool(board: SessionTasks.board),
            IdeasTool(board: SessionTasks.ideas, tasks: SessionTasks.board)
        ] + (skills.tool.map { [$0] } ?? []) + (askPerson == nil ? [] : [QuestionTool()])
            + (startSubagent == nil ? [] : [AgentTool()]),
        live: live
    )
    let context = ToolContext(
        workingDirectory: workingDirectory,
        outputDirectory: SessionDirectory(project: workingDirectory, environment: LaunchEnvironment.values).path
            + "/output",
        sandbox: sandbox,
        approve: approve,
        narrowing: narrowing,
        commandEnvironment: run.commandEnvironment,
        destructiveApprover: destructiveApprover,
        imageLimits: run.model.imageLimits,
        callGate: callGate,
        askPerson: askPerson,
        progress: progress,
        startSubagent: startSubagent
    )
    return AgentLoop(
        provider: deferringThinking(makeProvider(resolved, transport: transport), run: run, limit: agent.maximumTokens),
        tools: tools,
        settings: agent,
        context: context,
        hooks: checkHooks(run.configuration.hooks.value, tools: tools, context: context, reportEvent: reportEvent),
        // Offline, a failed request waits for the network instead of spending its retries (roadmap 0141).
        network: SystemNetworkPath()
    )
}
