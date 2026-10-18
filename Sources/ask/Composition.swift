/// The wiring shared by the interactive screen and `ask -p`. Binding only: behaviour lives in the libraries.

internal import AemiJSON
internal import AskAI
internal import AskAgentCore
internal import AskTools
internal import Foundation

/// Adapts the Anthropic client to the loop, resolving auth per request so a long run survives a refresh.
struct ClaudeProvider: ModelProvider {
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

/// Signed out, said so a person can act on it.
struct NotSignedIn: Error, CustomStringConvertible {
    var description: String { "not signed in. Run `ask login`, or set ANTHROPIC_API_KEY." }
}

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

/// The agent loop with the four tools, rooted at `workingDirectory`.
func makeLoop(model: String, workingDirectory: String, transport: URLSessionTransport) throws -> AgentLoop {
    let environment = ProcessInfo.processInfo.environment
    return AgentLoop(
        provider: ClaudeProvider(
            client: AnthropicClient(transport: transport, endpoint: AnthropicClient.endpoint(environment: environment)),
            auth: requestAuth(transport: transport)),
        tools: try ToolRegistry(FileTools.all + [BashTool()]),
        settings: AgentSettings(
            model: model, maximumTokens: 16_384, systemPrompt: [instructions(workingDirectory: workingDirectory)],
            maximumTurns: 100),
        context: ToolContext(workingDirectory: workingDirectory))
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
