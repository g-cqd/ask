internal import AemiJSON
internal import Testing

@testable import AskAI

/// Claude's thinking text is asked for (2026-10-30 wish): models from Opus 4.7 on default to `display: "omitted"`, which streams thinking
/// blocks with empty text, so ask showed empty blocks where Pi, which asks for `"summarized"`, showed the model's reasoning. A thinking
/// configuration that takes `display` asks for the summary; on a model that always thinks, the provider's default is sent as the
/// adaptive thinking it is, so the summary can be asked for too.
@Suite("Claude's thinking is asked for as readable summaries")
struct ThinkingDisplayTests {
    private func body(_ control: ThinkingControl?) throws -> JSON {
        let request = ModelRequest(
            model: "m", maxTokens: 32000, systemPrompt: [],
            messages: [ModelMessage(role: .user, blocks: [.text("hi")])],
            tools: [], thinking: control)
        return try AemiJSON.parse(AnthropicRequestEncoder.encode(request, caching: false)).root
    }

    @Test func `adaptive and budgeted thinking ask for the summary`() throws {
        #expect(try body(.effort(.high))["thinking"]["display"].string == "summarized")
        #expect(try body(.budget(tokens: 8192, effort: nil))["thinking"]["display"].string == "summarized")
    }

    @Test func `the modes that take no display are sent without one`() throws {
        #expect(try !body(.disabled)["thinking"]["display"].exists)
        #expect(try !body(.betweenTools)["thinking"]["display"].exists, "between_tools takes no other field")
    }

    @Test func `the model's own adaptive thinking is sent without an effort, with the summary asked for`() throws {
        let sent = try body(.adaptive)
        #expect(sent["thinking"]["type"].string == "adaptive" && sent["thinking"]["display"].string == "summarized")
        #expect(!sent["output_config"].exists, "the provider's default effort")
    }

    @Test func `the provider's default is adaptive thinking only on a model that cannot stop thinking`() {
        let always = CatalogModel(id: "claude-opus-5-5", thinkingModes: [.adaptive])
        let sonnet = CatalogModel(id: "claude-sonnet-5-5", thinkingModes: [.adaptive, .betweenTools])
        let optional = CatalogModel(id: "claude-opus-4-8", thinkingModes: [.disabled, .adaptive])
        let legacy = CatalogModel(id: "claude-sonnet-4-5", thinkingModes: [.disabled, .enabled])
        #expect(ThinkingControl.providerDefault(descriptor: always) == .adaptive)
        #expect(ThinkingControl.providerDefault(descriptor: sonnet) == .adaptive)
        #expect(ThinkingControl.providerDefault(descriptor: optional) == nil, "Opus 4.8 does not think unless asked")
        #expect(ThinkingControl.providerDefault(descriptor: legacy) == nil)
        #expect(ThinkingControl.providerDefault(descriptor: nil) == nil, "unknown: nothing is sent")
    }

    /// The lookup made before the first request when the cached catalog cannot be used (a subscription's token was refreshed, so the
    /// cache belongs to another scope) chooses through `select`; the default level must reach the same answer there.
    @Test func `selecting the provider's default from a looked-up catalog asks for the summary`() throws {
        let model = ResolvedModel(provider: .anthropic, model: "claude-opus-5-5")
        let always = CatalogModel(id: "claude-opus-5-5", thinkingModes: [.adaptive])
        let optional = CatalogModel(id: "claude-opus-5-5", thinkingModes: [.disabled, .adaptive])
        #expect(
            try ThinkingControl.select(.providerDefault, model: model, descriptor: always, maximumTokens: 64)
                == .adaptive)
        #expect(
            try ThinkingControl.select(.providerDefault, model: model, descriptor: optional, maximumTokens: 64) == nil)
        #expect(try ThinkingControl.select(.providerDefault, model: model, descriptor: nil, maximumTokens: 64) == nil)
    }
}
