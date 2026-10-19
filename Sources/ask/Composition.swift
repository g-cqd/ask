/// The wiring shared by the interactive screen and `ask -p`. Binding only: behaviour lives in the libraries.

internal import AemiJSON
internal import AskAI
internal import AskAgentCore
internal import AskTools
internal import Foundation

/// Auth for each request: `ANTHROPIC_API_KEY` when set, else the stored subscription, refreshed as needed.
func requestAuth(transport: URLSessionTransport) -> @Sendable () async throws -> AnthropicClient.Auth {
    if let key = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !key.isEmpty {
        return { .apiKey(key) }
    }
    let access = ClaudeAccess(file: .standard(), client: ClaudeAuthClient(transport: transport))
    return {
        do {
            return try await access.auth(now: Date().timeIntervalSince1970)
        } catch ClaudeAccessError.signedOut {
            throw NotSignedIn()
        }
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

/// The loop's provider for `resolved`, sending through `transport`.
func makeProvider(_ resolved: ResolvedModel, transport: URLSessionTransport) -> any ModelProvider {
    switch resolved.provider {
        case .anthropic:
            ClaudeProvider(
                client: AnthropicClient(
                    transport: transport,
                    endpoint: AnthropicClient.endpoint(environment: ProcessInfo.processInfo.environment)),
                auth: requestAuth(transport: transport))
        case .openAICompatible(_, let baseURL, let apiKey, let headers):
            OpenAICompatibleProvider(
                client: OpenAICompatibleClient(transport: transport, baseURL: baseURL, apiKey: apiKey, headers: headers)
            )
        case .openAIResponses(_, let baseURL, let apiKey, let headers):
            ResponsesProvider(
                client: ResponsesClient(transport: transport, baseURL: baseURL, apiKey: apiKey, headers: headers))
    }
}

/// How the model is named to the user: `model`, or `provider/model` for a configured provider.
func modelLabel(_ resolved: ResolvedModel) -> String {
    switch resolved.provider {
        case .openAICompatible(let name, _, _, _), .openAIResponses(let name, _, _, _):
            return "\(name)/\(resolved.model)"
        case .anthropic: break
    }
    return resolved.model
}

/// The agent loop with the tools, rooted at `workingDirectory`, following `instructions` after ask's own. Jobs
/// live in `jobs`, which the caller stops when ask exits.
func makeLoop(
    model resolved: ResolvedModel, workingDirectory: String, instructions files: [ProjectInstructions.File],
    limits: RunLimits, jobs: JobTable, transport: URLSessionTransport
) throws -> AgentLoop {
    AgentLoop(
        provider: makeProvider(resolved, transport: transport),
        tools: try ToolRegistry(
            FileTools.all + [
                BashTool(jobs: jobs), WaitTool(jobs: jobs), JobInputTool(jobs: jobs), JobStopTool(jobs: jobs)
            ]),
        settings: settings(for: resolved, workingDirectory: workingDirectory, instructions: files, limits: limits),
        context: ToolContext(
            workingDirectory: workingDirectory,
            outputDirectory: SessionDirectory(project: workingDirectory).path + "/output"))
}

/// The run's settings, with the reply limit, compaction threshold and kept tail sized to the model's window.
private func settings(
    for resolved: ResolvedModel, workingDirectory: String, instructions files: [ProjectInstructions.File],
    limits: RunLimits
) -> AgentSettings {
    let budget = ContextBudget(
        contextWindow: resolved.contextWindow, maxOutputTokens: resolved.maxOutputTokens,
        requestedCompactAt: limits.compactAtTokens)
    return AgentSettings(
        model: resolved.model, maximumTokens: budget.maximumTokens,
        systemPrompt: [instructions(workingDirectory: workingDirectory)] + ProjectInstructions.promptBlocks(files),
        maximumTurns: limits.maximumTurns, compactAtTokens: budget.compactAtTokens,
        keepRecentBytes: budget.keepRecentBytes, toolOutputBytes: budget.toolOutputBytes)
}

/// ask's instructions, carried in the first user message (ADR-0007).
private func instructions(workingDirectory: String) -> String {
    """
    You are ask, a coding agent working in a terminal on macOS. The working directory is \(workingDirectory). \
    Use the tools to read, write and edit files and to run bash commands; relative paths resolve against the \
    working directory. Start servers, watchers and long builds with bash yield_seconds, then use wait, job_input \
    and job_stop; stop the jobs you started when you no longer need them. Prefer small changes you have verified, by running the build or tests when there are any. \
    Answer concisely, and say plainly what you did not verify.
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
