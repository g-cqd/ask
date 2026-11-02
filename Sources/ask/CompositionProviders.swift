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
    progress: ToolProgressReporter? = nil
) throws -> AgentLoop {
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
    return AgentLoop(
        provider: deferringThinking(makeProvider(resolved, transport: transport), run: run, limit: agent.maximumTokens),
        tools: try ToolRegistry(
            FileTools.all + [
                BashTool(jobs: jobs, commandEnvironment: run.commandEnvironment), JobActionTool(jobs: jobs),
                NarrowSandboxTool(jobs: jobs), TasksTool(board: SessionTasks.board),
                IdeasTool(board: SessionTasks.ideas, tasks: SessionTasks.board)
            ] + (skills.tool.map { [$0] } ?? []) + (askPerson == nil ? [] : [QuestionTool()]),
            live: live
        ),
        settings: agent,
        context: ToolContext(
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
            progress: progress
        ),
        // Offline, a failed request waits for the network instead of spending its retries (roadmap 0141).
        network: SystemNetworkPath()
    )
}
