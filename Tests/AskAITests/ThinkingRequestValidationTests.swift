internal import Foundation
internal import Testing

@testable import AskAI

struct ThinkingRequestValidationTests {
    private func request(_ control: ThinkingControl, maximum: Int = 32000) -> ModelRequest {
        ModelRequest(model: "m", maxTokens: maximum, systemPrompt: [], messages: [], tools: [], thinking: control)
    }

    @Test(arguments: [
        (ThinkingControl.effort(.providerDefault), 32000), (.effort(.off), 32000),
        (.budget(tokens: -1, effort: nil), 32000), (.budget(tokens: 1023, effort: nil), 32000),
        (.budget(tokens: 1024, effort: nil), 1024), (.budget(tokens: Int.max, effort: nil), 32000),
        (.budget(tokens: 1024, effort: .off), 32000), (.budget(tokens: 1024, effort: .providerDefault), 32000)
    ])
    func `invalid native controls fail before transport`(_ control: ThinkingControl, _ maximum: Int) async {
        let transport = ScriptedTransport(status: 401, chunks: [])
        let client = AnthropicClient(transport: transport)
        var failure: (any Error)?
        do { for try await _ in client.stream(request(control, maximum: maximum), auth: .apiKey("fixture")) {} } catch {
            failure = error
        }
        #expect(failure is ThinkingError)
        #expect(transport.sent == nil)
    }

    @Test(arguments: [
        ThinkingControl.effort(.providerDefault), .effort(.off), .betweenTools, .budget(tokens: 1024, effort: nil)
    ])
    func `native-only modes and reset spellings are not silently omitted from Responses`(_ control: ThinkingControl)
        async
    {
        let transport = ScriptedTransport(status: 401, chunks: [])
        let client = ResponsesClient(transport: transport, baseURL: URL(string: "https://example.test/v1")!)
        var failure: (any Error)?
        do { for try await _ in client.stream(request(control)) {} } catch { failure = error }
        #expect(failure is ThinkingError)
        #expect(transport.sent == nil)
    }

    @Test(arguments: [ThinkingControl.disabled, .betweenTools, .effort(.high), .budget(tokens: 1024, effort: nil)])
    func `valid native controls, including the minimum budget below its output ceiling, reach transport`(
        _ control: ThinkingControl
    ) async {
        let transport = ScriptedTransport(status: 401, chunks: [])
        let client = AnthropicClient(transport: transport)
        var failure: (any Error)?
        do { for try await _ in client.stream(request(control, maximum: 1100), auth: .apiKey("fixture")) {} } catch {
            failure = error
        }
        #expect(failure != nil && !(failure is ThinkingError))
        #expect(transport.sent != nil)
    }
}
