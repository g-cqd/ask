internal import Foundation
internal import Testing

@testable import AskAI

struct ThinkingControlTests {
    private static let native = ResolvedModel(provider: .anthropic, model: "native")
    private static let codex = ResolvedModel(provider: .codex, model: "gpt-6.1-sol")
    private static let responses = ResolvedModel(
        provider: .openAIResponses(
            name: "api", baseURL: URL(string: "https://example.test/v1")!, apiKey: nil, headers: [:]), model: "m")
    private static let adaptive = CatalogModel(
        id: "native", reasoningLevels: ["low", "medium", "high", "xhigh", "max"], supportsThinking: true,
        thinkingModes: [.adaptive, .betweenTools])

    @Test func `default means no request override on every protocol`() throws {
        let chat = ResolvedModel(
            provider: .openAICompatible(
                name: "chat", baseURL: URL(string: "https://example.test/v1")!, apiKey: nil, headers: [:]), model: "m")
        for model in [Self.native, Self.codex, Self.responses, chat] {
            let chosen = try ThinkingControl.select(.providerDefault, model: model, descriptor: nil, maximumTokens: 64)
            #expect(chosen == nil)
        }
    }

    @Test func `native off uses the reported off mode, not a model-name heuristic`() throws {
        let between = try ThinkingControl.select(.off, model: Self.native, descriptor: Self.adaptive, maximumTokens: 64)
        #expect(between == .betweenTools)
        let disabledModel = CatalogModel(id: "native", supportsThinking: true, thinkingModes: [.adaptive, .disabled])
        let disabled = try ThinkingControl.select(
            .off, model: Self.native, descriptor: disabledModel, maximumTokens: 64)
        #expect(disabled == .disabled)
        let alwaysOn = CatalogModel(id: "native", supportsThinking: true, thinkingModes: [.adaptive])
        #expect(throws: ThinkingError.self) {
            try ThinkingControl.select(.off, model: Self.native, descriptor: alwaysOn, maximumTokens: 64)
        }
    }

    @Test(arguments: [ThinkingLevel.low, .medium, .high, .xhigh, .max])
    func `a reported native effort is used exactly`(_ level: ThinkingLevel) throws {
        let chosen = try ThinkingControl.select(
            level, model: Self.native, descriptor: Self.adaptive, maximumTokens: 128)
        #expect(chosen == .effort(level))
    }

    @Test func `an unsupported native named effort is not clamped to low`() {
        #expect(throws: ThinkingError.self) {
            try ThinkingControl.select(.minimal, model: Self.native, descriptor: Self.adaptive, maximumTokens: 16384)
        }
    }

    @Test func `legacy thinking gets a visible concrete budget and room for an answer`() throws {
        let descriptor = CatalogModel(id: "native", supportsThinking: true, thinkingModes: [.enabled, .disabled])
        let high = try ThinkingControl.select(.high, model: Self.native, descriptor: descriptor, maximumTokens: 16384)
        #expect(high == .budget(tokens: 15360, effort: nil))
        let minimal = try ThinkingControl.select(
            .minimal, model: Self.native, descriptor: descriptor, maximumTokens: 2048)
        #expect(minimal == .budget(tokens: 1024, effort: nil))
        let max = try ThinkingControl.select(.max, model: Self.native, descriptor: descriptor, maximumTokens: 8192)
        #expect(max == .budget(tokens: 7168, effort: nil))
        #expect(throws: ThinkingError.insufficientOutput(minimum: 2048, available: 2047)) {
            try ThinkingControl.select(.low, model: Self.native, descriptor: descriptor, maximumTokens: 2047)
        }
    }

    @Test func `a legacy model's separately reported effort accompanies the budget only when supported`() throws {
        let descriptor = CatalogModel(
            id: "native", reasoningLevels: ["low", "high"], supportsThinking: true, thinkingModes: [.enabled])
        let high = try ThinkingControl.select(.high, model: Self.native, descriptor: descriptor, maximumTokens: 32000)
        #expect(high == .budget(tokens: 16384, effort: .high))
        let medium = try ThinkingControl.select(
            .medium, model: Self.native, descriptor: descriptor, maximumTokens: 32000)
        #expect(medium == .budget(tokens: 8192, effort: nil))
    }

    @Test func `an explicitly non-thinking native model needs no off field and cannot be enabled`() throws {
        let descriptor = CatalogModel(id: "native", supportsThinking: false)
        let off = try ThinkingControl.select(.off, model: Self.native, descriptor: descriptor, maximumTokens: 64)
        #expect(off == nil)
        #expect(throws: ThinkingError.self) {
            try ThinkingControl.select(.high, model: Self.native, descriptor: descriptor, maximumTokens: 2048)
        }
    }

    @Test func `unknown native metadata is not guessed and metadata from another model is not used`() {
        #expect(throws: ThinkingError.missingCapabilities(model: "native")) {
            try ThinkingControl.select(.off, model: Self.native, descriptor: nil, maximumTokens: 64)
        }
        #expect(throws: ThinkingError.missingCapabilities(model: "native")) {
            try ThinkingControl.select(
                .high, model: Self.native,
                descriptor: CatalogModel(
                    id: "other", reasoningLevels: ["high"], supportsThinking: true, thinkingModes: [.adaptive]),
                maximumTokens: 2048)
        }
    }

    @Test func `Codex efforts follow known reported choices and off is not secretly low`() throws {
        let descriptor = CatalogModel(
            id: "gpt-6.1-sol", reasoningLevels: ["low", "medium", "high", "xhigh", "max", "ultra"])
        let high = try ThinkingControl.select(.high, model: Self.codex, descriptor: descriptor, maximumTokens: 64)
        #expect(high == .effort(.high))
        #expect(throws: ThinkingError.self) {
            try ThinkingControl.select(.off, model: Self.codex, descriptor: descriptor, maximumTokens: 64)
        }
        #expect(throws: ThinkingError.self) {
            try ThinkingControl.select(.minimal, model: Self.codex, descriptor: descriptor, maximumTokens: 64)
        }
        #expect(ThinkingLevel(rawValue: "ultra") == nil, "advertised ultra was rejected by the live inference schema")
    }

    @Test func `unknown Responses capabilities forward a requested standard control without claiming validation`()
        throws
    {
        let high = try ThinkingControl.select(.high, model: Self.responses, descriptor: nil, maximumTokens: 64)
        #expect(high == .effort(.high))
        let off = try ThinkingControl.select(.off, model: Self.responses, descriptor: nil, maximumTokens: 64)
        #expect(off == .disabled)
    }

    @Test func `unverified chat-completions thinking is refused rather than ignored`() {
        let chat = ResolvedModel(
            provider: .openAICompatible(
                name: "chat", baseURL: URL(string: "https://example.test/v1")!, apiKey: nil, headers: [:]), model: "m")
        #expect(throws: ThinkingError.self) {
            try ThinkingControl.select(.high, model: chat, descriptor: nil, maximumTokens: 2048)
        }
    }
}
