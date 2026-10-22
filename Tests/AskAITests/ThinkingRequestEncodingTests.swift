internal import AemiJSON
internal import Foundation
internal import Testing

@testable import AskAI

struct ThinkingRequestEncodingTests {
    private func request(_ control: ThinkingControl? = nil, maxTokens: Int = 32000) -> ModelRequest {
        ModelRequest(
            model: "m", maxTokens: maxTokens, systemPrompt: [],
            messages: [ModelMessage(role: .user, blocks: [.text("hi")])], tools: [], thinking: control)
    }
    private func root(_ bytes: [UInt8]) throws -> JSON { try AemiJSON.parse(bytes).root }

    @Test func `no selected control leaves every existing wire protocol alone`() throws {
        let value = request()
        let anthropic = try root(AnthropicRequestEncoder.encode(value, caching: false))
        let responses = try root(ResponsesRequestEncoder.encode(value))
        let chat = try root(OpenAIRequestEncoder.encode(value))
        #expect(!anthropic["thinking"].exists && !anthropic["output_config"].exists)
        #expect(!responses["reasoning"].exists)
        #expect(!chat["reasoning_effort"].exists)
    }

    @Test(arguments: [ThinkingLevel.minimal, .low, .medium, .high, .xhigh, .max])
    func `Responses effort is exact and requests a provider summary`(_ level: ThinkingLevel) throws {
        let body = try root(ResponsesRequestEncoder.encode(request(.effort(level))))
        #expect(body["reasoning"]["effort"].string == level.rawValue)
        #expect(body["reasoning"]["summary"].string == "auto")
    }

    @Test func `Responses off is none and asks for no reasoning summary`() throws {
        let body = try root(ResponsesRequestEncoder.encode(request(.disabled)))
        #expect(body["reasoning"]["effort"].string == "none")
        #expect(!body["reasoning"]["summary"].exists)
    }

    @Test func `Codex keeps its no-output-limit dialect while selecting an effort`() throws {
        let body = try root(
            ResponsesRequestEncoder.encode(request(.effort(.high)), dialect: ResponsesDialect(sendsOutputLimit: false)))
        #expect(body["reasoning"]["effort"].string == "high")
        #expect(!body["max_output_tokens"].exists)
    }

    @Test(arguments: [ThinkingLevel.low, .medium, .high, .xhigh, .max])
    func `native adaptive thinking carries the selected effort`(_ level: ThinkingLevel) throws {
        let body = try root(AnthropicRequestEncoder.encode(request(.effort(level)), caching: false))
        #expect(body["thinking"]["type"].string == "adaptive")
        #expect(body["output_config"]["effort"].string == level.rawValue)
        #expect(!body["thinking"]["budget_tokens"].exists)
    }

    @Test func `native off modes are distinct and never carry an effort or a budget`() throws {
        let disabled = try root(AnthropicRequestEncoder.encode(request(.disabled), caching: false))
        #expect(disabled["thinking"]["type"].string == "disabled")
        #expect(!disabled["output_config"].exists && !disabled["thinking"]["budget_tokens"].exists)
        let between = try root(AnthropicRequestEncoder.encode(request(.betweenTools), caching: false))
        #expect(between["thinking"]["type"].string == "between_tools")
        #expect(!between["output_config"].exists)
    }

    @Test func `legacy thinking carries its concrete budget and only a selected supported effort`() throws {
        let plain = try root(
            AnthropicRequestEncoder.encode(request(.budget(tokens: 8192, effort: nil)), caching: false))
        #expect(plain["thinking"]["type"].string == "enabled")
        #expect(plain["thinking"]["budget_tokens"].int == 8192)
        #expect(!plain["output_config"].exists)
        let effort = try root(
            AnthropicRequestEncoder.encode(request(.budget(tokens: 8192, effort: .medium)), caching: false))
        #expect(effort["output_config"]["effort"].string == "medium")
    }

    @Test func `clients refuse incompatible or invalid controls before sending anything`() async {
        let responseTransport = ScriptedTransport(status: 200, chunks: [])
        let responses = ResponsesClient(transport: responseTransport, baseURL: URL(string: "https://example.test/v1")!)
        var responseFailure: (any Error)?
        do { for try await _ in responses.stream(request(.betweenTools)) {} } catch { responseFailure = error }
        #expect(responseFailure is ThinkingError)
        #expect(responseTransport.sent == nil)

        let nativeTransport = ScriptedTransport(status: 200, chunks: [])
        let native = AnthropicClient(transport: nativeTransport)
        var nativeFailure: (any Error)?
        do {
            for try await _ in native.stream(request(.budget(tokens: 1, effort: nil)), auth: .apiKey("fixture")) {}
        } catch { nativeFailure = error }
        #expect(nativeFailure is ThinkingError)
        #expect(nativeTransport.sent == nil)

        let chatTransport = ScriptedTransport(status: 200, chunks: [])
        let chat = OpenAICompatibleClient(transport: chatTransport, baseURL: URL(string: "https://example.test/v1")!)
        var chatFailure: (any Error)?
        do { for try await _ in chat.stream(request(.effort(.high))) {} } catch { chatFailure = error }
        #expect(chatFailure is ThinkingError)
        #expect(chatTransport.sent == nil)
    }
}
