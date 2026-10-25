/// The wiring shared by the interactive screen and `ask -p`. Binding only: behaviour lives in the libraries.

internal import AemiJSON
internal import AskAI
internal import AskAgentCore
internal import AskTools
internal import Foundation

/// Auth for each request: the environment's credential when it names one (`ANTHROPIC_AUTH_TOKEN`, then `ANTHROPIC_OAUTH_TOKEN`,
/// then `ANTHROPIC_API_KEY`), else the stored subscription, refreshed as needed. A named connection ignores the environment.
func requestAuth(transport: URLSessionTransport, connection: ConnectionRecord? = nil)
    -> @Sendable () async throws -> AnthropicClient.Auth
{
    requestAuth(
        AnthropicAuthorization(
            file: NamedConnections.file(for: connection), connection: connection, transport: transport))
}

/// ``requestAuth(transport:connection:)`` over an authorization the caller keeps, to ask it more than for auth.
func requestAuth(_ authorization: AnthropicAuthorization) -> @Sendable () async throws -> AnthropicClient.Auth {
    {
        try await authorization.auth(
            environment: ProcessInfo.processInfo.environment, now: Date().timeIntervalSince1970)
    }
}

/// ask's configuration directory: `$XDG_CONFIG_HOME/ask` when that is absolute, else `~/.config/ask`.
func askConfigDirectory(environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
    let base = environment["XDG_CONFIG_HOME"].flatMap { $0.hasPrefix("/") ? $0 : nil } ?? NSHomeDirectory() + "/.config"
    return base + "/ask"
}

/// The project's instruction files for `workingDirectory` (AGENTS.md / CLAUDE.md), outermost first.
func instructionFiles(workingDirectory: String) -> [ProjectInstructions.File] {
    ProjectInstructions.discover(
        from: workingDirectory, home: NSHomeDirectory(), configDirectory: askConfigDirectory())
}

/// One line per instruction file, for the user: what was loaded and what was skipped.
func describe(_ files: [ProjectInstructions.File]) -> [String] {
    files.map { file in
        file.skippedBecause.map { "Skipped \(file.path): \($0)." } ?? "Instructions loaded from \(file.path)."
    }
}

/// Fails fast, before any work, when there is no way to authenticate: exit 77 with what to do. A configured provider has no
/// sign-in to check.
func requireSignIn(for model: ResolvedModel, transport: URLSessionTransport) async {
    do {
        switch model.provider {
            case .anthropic: _ = try await requestAuth(transport: transport, connection: model.connection)()
            case .codex:
                let access = CodexAccess(
                    file: NamedConnections.file(for: model.connection), client: CodexAuthClient(transport: transport),
                    connection: model.connection)
                _ = try await access.credentials(now: Date().timeIntervalSince1970)
            case .agy: _ = try await makeAgyAccess(transport: transport).session(now: Date().timeIntervalSince1970)
            case .openAICompatible, .openAIResponses: return
        }
    } catch {
        if let connection = model.connection, case CodexAccessError.signedOut = error {
            fail("ask: \(ConnectionError.signInRequired(name: connection.name, provider: .codex))", code: 77)
        }
        fail("ask: \(error)", code: 77)
    }
}

/// The loop's provider for `resolved`, sending through `transport`.
func makeProvider(_ resolved: ResolvedModel, transport: URLSessionTransport) -> any ModelProvider {
    switch resolved.provider {
        case .anthropic:
            claudeProvider(resolved, transport: transport)
        case .codex:
            codexProvider(resolved, transport: transport)
        case .agy: agyProvider(transport: transport)
        case .openAICompatible(_, let baseURL, let apiKey, let headers):
            OpenAICompatibleProvider(
                client: OpenAICompatibleClient(transport: transport, baseURL: baseURL, apiKey: apiKey, headers: headers)
            )
        case .openAIResponses(_, let baseURL, let apiKey, let headers):
            ResponsesProvider(
                client: ResponsesClient(transport: transport, baseURL: baseURL, apiKey: apiKey, headers: headers))
    }
}

/// Claude's provider, which says so once when a refreshed sign-in could not be saved (ADR-0091).
private func claudeProvider(_ resolved: ResolvedModel, transport: URLSessionTransport) -> any ModelProvider {
    let authorization = AnthropicAuthorization(
        file: NamedConnections.file(for: resolved.connection), connection: resolved.connection, transport: transport)
    let notice = RotationNotice(provider: "Claude")
    return NoticingProvider(
        base: ClaudeProvider(
            client: AnthropicClient(
                transport: transport,
                endpoint: AnthropicClient.endpoint(
                    environment: resolved.connection == nil ? ProcessInfo.processInfo.environment : [:])),
            auth: requestAuth(authorization)),
        notice: { notice.message(unsavedBecause: authorization.unsavedReason) })
}

/// Codex's provider, which says so once when a refreshed sign-in could not be saved (ADR-0091).
private func codexProvider(_ resolved: ResolvedModel, transport: URLSessionTransport) -> any ModelProvider {
    let access = CodexAccess(
        file: NamedConnections.file(for: resolved.connection), client: CodexAuthClient(transport: transport),
        connection: resolved.connection)
    let notice = RotationNotice(provider: "Codex")
    return NoticingProvider(
        base: CodexProvider(access: access, transport: transport, session: UUID().uuidString),
        notice: { notice.message(unsavedBecause: access.unsavedReason) })
}

/// Antigravity's provider, which says so once when a refreshed sign-in could not be saved (ADR-0091).
private func agyProvider(transport: URLSessionTransport) -> any ModelProvider {
    let access = makeAgyAccess(transport: transport)
    let notice = RotationNotice(provider: "Antigravity")
    return NoticingProvider(
        base: AgyProvider(access: access, client: AgyClient(transport: transport)),
        notice: { notice.message(unsavedBecause: access.unsavedReason) })
}

/// How the model is named to the user: `model`, or `provider/model` for a configured provider.
func modelLabel(_ resolved: ResolvedModel) -> String {
    if let connection = resolved.connection { return "\(connection.name)/\(resolved.model)" }
    switch resolved.provider {
        case .openAICompatible(let name, _, _, _), .openAIResponses(let name, _, _, _):
            return "\(name)/\(resolved.model)"
        case .codex: return "codex/\(resolved.model)"
        case .agy: return "agy/\(resolved.model)"
        case .anthropic: break
    }
    return resolved.model
}

/// The agent loop with the tools, rooted at `workingDirectory`, following `instructions` after ask's own. Jobs
/// live in `jobs`, which the caller stops when ask exits.
func makeLoop(
    _ run: RunSettings, instructions files: [ProjectInstructions.File], jobs: JobTable,
    transport: URLSessionTransport, approve: SandboxApprover? = nil, narrowing: SessionNarrowing = SessionNarrowing(),
    live: LiveTools? = nil, destructiveApprover: DestructiveApprover? = nil
) throws -> AgentLoop {
    let workingDirectory = run.workspace
    let resolved = run.model
    let limits = run.limits
    let sandbox = run.sandbox
    let skills = SkillBook(run.configuration.skills.value, workingDirectory: workingDirectory)
    let agent = settings(
        for: resolved, workingDirectory: workingDirectory,
        followedBy: (skills.block.map { [$0] } ?? []) + ProjectInstructions.promptBlocks(files), limits: limits,
        sandbox: sandbox, thinking: run.thinking)
    return AgentLoop(
        provider: deferringThinking(makeProvider(resolved, transport: transport), run: run, limit: agent.maximumTokens),
        tools: try ToolRegistry(
            FileTools.all + [
                BashTool(jobs: jobs), WaitTool(jobs: jobs), JobInputTool(jobs: jobs), JobStopTool(jobs: jobs),
                NarrowSandboxTool(jobs: jobs)
            ] + (skills.tool.map { [$0] } ?? []), live: live),
        settings: agent,
        context: ToolContext(
            workingDirectory: workingDirectory,
            outputDirectory: SessionDirectory(project: workingDirectory).path + "/output", sandbox: sandbox,
            approve: approve, narrowing: narrowing, commandEnvironment: run.commandEnvironment,
            destructiveApprover: destructiveApprover))
}

/// The provider, with a control still to be looked up wrapped to look it up before the first request, not at startup.
private func deferringThinking(_ provider: any ModelProvider, run: RunSettings, limit: Int) -> any ModelProvider {
    guard run.thinkingPending else { return provider }
    let level = run.configuration.thinking.value
    let model = run.model
    let environment = ProcessInfo.processInfo.environment
    return DeferredThinkingProvider(inner: provider) {
        try await ThinkingDiscovery.lookup(level, model: model, environment: environment, maximumTokens: limit)
    }
}

/// The run's settings, with the reply limit, compaction threshold and kept tail sized to the model's window. ask's own instructions come first and `blocks`
/// (the skills, then the project's instruction files) follow.
private func settings(
    for resolved: ResolvedModel, workingDirectory: String, followedBy blocks: [String], limits: RunLimits,
    sandbox: SandboxPolicy, thinking: ThinkingControl?
) -> AgentSettings {
    let budget = ContextBudget(
        contextWindow: resolved.contextWindow, maxOutputTokens: resolved.maxOutputTokens,
        requestedCompactAt: limits.compactAtTokens)
    return AgentSettings(
        model: resolved.model, maximumTokens: budget.maximumTokens,
        systemPrompt: [instructions(workingDirectory: workingDirectory, sandbox: sandbox)] + blocks,
        maximumTurns: limits.maximumTurns, compactAtTokens: budget.compactAtTokens,
        keepRecentBytes: budget.keepRecentBytes, toolOutputBytes: budget.toolOutputBytes, thinking: thinking)
}

/// `ask --self-check`: starts everything a run starts, without a network, so a reload can tell a build that works
/// from one that does not (ADR-0033). The settings are already loaded: this build has read this configuration
/// with its own parser, which is the part a new build most often gets wrong.
func checkSelf(_ settings: RunSettings) {
    do {
        _ = try makeLoop(
            settings, instructions: [], jobs: JobTable(),
            transport: URLSessionTransport())
    } catch {
        fail("ask: \(error)", code: 70)
    }
    print("ask self-check ok")
}

/// ask's instructions, carried in the first user message (ADR-0007).
private func instructions(workingDirectory: String, sandbox: SandboxPolicy) -> String {
    let rules = sandbox.summary.map { " " + $0 } ?? ""
    return """
        You are ask, a coding agent working in a terminal on macOS. The working directory is \(workingDirectory). \
        Use the tools to read, write and edit files and to run bash commands; relative paths resolve against the \
        working directory. Start servers, watchers and long builds with bash yield_seconds, then use wait, job_input \
        and job_stop; stop the jobs you started when you no longer need them. Prefer small changes you have verified, by running the build or tests when there are any. \
        Answer concisely, and say plainly what you did not verify.\(rules)
        """
}

/// A short description of a tool call for a one-line display: the command or the path when there is one.
func toolSummary(name: String, input: JSONObject) -> String {
    struct Fields: Decodable {
        let command: String?
        let path: String?
    }
    let fields = try? AemiJSON.JSONDecoder().decode(Fields.self, from: input.bytes)
    let summary = fields?.command ?? fields?.path ?? String(decoding: input.bytes, as: UTF8.self)
    let firstLine = summary.split(separator: "\n").first.map(String.init) ?? summary
    return firstLine.count > 160 ? String(firstLine.prefix(160)) + "…" : firstLine
}

/// A retry, said for a person: what failed, how long ask waits, and which attempt comes next.
/// What a compaction's notice says.
func compactionNotice(_ event: AgentEvent) -> String? {
    switch event {
        case .compacted(let summary, _):
            "Compacted the conversation: earlier messages are now a \(summary.count)-character summary. "
                + "The session file keeps them all."
        case .compactionFailed(let reason): "Could not compact (\(reason)); continuing with the whole conversation."
        default: nil
    }
}

func retryNotice(attempt: Int, of total: Int, delay: Duration, reason: String) -> String {
    let milliseconds = delay.components.seconds * 1_000 + delay.components.attoseconds / 1_000_000_000_000_000
    let wait = milliseconds % 1_000 == 0 ? "\(milliseconds / 1_000) s" : "\(Double(milliseconds) / 1_000) s"
    return "\(reason); retrying in \(wait) (attempt \(attempt) of \(total))."
}
