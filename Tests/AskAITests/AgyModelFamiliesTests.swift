internal import Foundation
internal import Testing

@testable import AskAI

/// Antigravity lists each model's efforts as models of their own (`claude-opus-5-5-high`), grouped under a family name the server no
/// longer takes as an id (`groupedModels`). The family is kept as an entry whose levels are its variants, so a session or a choice that
/// names it resolves to a variant instead of a 404. Against a list recorded from a real account on 2026-11-25 under ask's own identity
/// (two families of the 37 models kept, the quota figures removed).
struct AgyModelFamiliesTests {
    private static let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Fixtures/Agy/model-list-efforts.json")

    private func recorded() async throws -> AgyModelList {
        let body = String(decoding: try Data(contentsOf: Self.fixture), as: UTF8.self)
        return try await AgyCloudClient(transport: SequencedTransport([.json(200, body)]))
            .models(accessToken: "access-test", project: "ask-test-project-1")
    }

    private func entry(_ list: AgyModelList, _ id: String) -> CatalogModel? { list.models.first { $0.id == id } }

    @Test func `each family is an entry whose levels are its variants, listed before them`() async throws {
        let list = try await recorded()
        let neon = try #require(entry(list, "gemini-4-neon"))
        #expect(neon.reasoningLevels == ["low", "medium", "high", "xhigh"])
        #expect(neon.defaultReasoningLevel == "high", "the server's default agent model is its high variant")
        #expect(neon.contextWindow == 1_048_576 && neon.maxOutputTokens == 262_144 && neon.unsuitable == nil)
        let opus = try #require(entry(list, "claude-opus-5-5"))
        #expect(opus.reasoningLevels == ["low", "medium", "high"])
        #expect(opus.defaultReasoningLevel == "high", "no server default in the family: high, when offered")
        let ids = list.models.map(\.id)
        #expect(
            ids.prefix(2) == ["gemini-4-neon", "claude-opus-5-5"],
            "families first, in the order of their first variant"
        )
        #expect(
            ids.contains("claude-opus-5-5-low") && ids.contains("gemini-4-neon-xhigh"),
            "the variants stay pickable"
        )
        #expect(list.defaultModelID == "gemini-4-neon-high")
        #expect(entry(list, "tab_flash_lite_preview")?.unsuitable == "tab completion")
    }

    @Test func `a family keeps only usable variants, needs one, and never shadows a listed model`() async throws {
        let body = """
            {"models":{"fam-low":{"supportsThinking":true},"fam-ultra":{"supportsThinking":true},"img-high":{"supportsThinking":true},
            "solo":{"supportsThinking":true},"solo-high":{"supportsThinking":true}},
            "imageGenerationModelIds":["img-high"],
            "groupedModels":{"fam":{"supportedThinkingLevels":[{"thinkingSuffix":"low"},{"thinkingSuffix":"ultra"},
            {"thinkingSuffix":"high"}]},"img":{"supportedThinkingLevels":[{"thinkingSuffix":"high"}]},
            "solo":{"supportedThinkingLevels":[{"thinkingSuffix":"high"}]}}}
            """
        let list = try await AgyCloudClient(transport: SequencedTransport([.json(200, body)]))
            .models(accessToken: "access-test", project: "ask-test-project-1")
        let fam = try #require(entry(list, "fam"))
        #expect(
            fam.reasoningLevels == ["low"] && fam.defaultReasoningLevel == "low",
            "no high variant, no unknown suffix"
        )
        #expect(entry(list, "img") == nil, "an image model's variant is no chat family")
        #expect(list.models.filter { $0.id == "solo" }.count == 1 && entry(list, "solo")?.reasoningLevels == [])
    }

    @Test
    func `a family's default effort is sent with no level chosen, a level it offers when chosen, and others refused`()
        throws
    {
        let family = CatalogModel(
            id: "claude-opus-5-5",
            reasoningLevels: ["low", "medium", "high"],
            defaultReasoningLevel: "high"
        )
        let model = ResolvedModel(provider: .agy, model: "claude-opus-5-5")
        func select(_ level: ThinkingLevel, _ descriptor: CatalogModel?) throws -> ThinkingControl? {
            try ThinkingControl.select(level, model: model, descriptor: descriptor, maximumTokens: 64_000)
        }
        #expect(try select(.providerDefault, family) == .effort(.high))
        #expect(try select(.low, family) == .effort(.low))
        #expect(
            throws: ThinkingError.unavailable(
                model: "claude-opus-5-5",
                level: .xhigh,
                available: ["low", "medium", "high"]
            )
        ) {
            try select(.xhigh, family)
        }
        #expect(try select(.providerDefault, nil) == nil, "unknown: the name is sent as it is")
        let variant = CatalogModel(id: "claude-opus-5-5", supportsThinking: true)
        #expect(throws: ThinkingError.unsupportedProtocol("Antigravity")) { try select(.high, variant) }
    }

    @Test func `the picker offers a family's efforts, verified, with the server's default`() {
        let family = CatalogModel(
            id: "gemini-4-neon",
            reasoningLevels: ["low", "medium", "high", "xhigh"],
            defaultReasoningLevel: "high"
        )
        let choices = ThinkingOptions.choices(for: .agy, descriptor: family)
        #expect(
            choices
                == ThinkingOptions.Choices(levels: [.low, .medium, .high, .xhigh], verified: true, serverDefault: .high)
        )
        #expect(ThinkingOptions.choices(for: .agy, descriptor: CatalogModel(id: "gemini-4-neon-high")) == nil)
    }
}
