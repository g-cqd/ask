internal import AemiJSON
internal import Foundation
internal import Testing

@testable import AskAI

/// Cloud Code's model list, against a body recorded from a real account on 2026-10-24 under ask's own identity (free text, the
/// account's address and quota figures removed, the project id replaced).
struct AgyModelListTests {
    private static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "Fixtures/Agy")

    private func models(_ json: String, status: Int = 200) async throws -> AgyModelList {
        try await AgyCloudClient(transport: SequencedTransport([.json(status, json)]))
            .models(accessToken: "access-test", project: "ask-test-project-1")
    }

    /// The models the filter of roadmap 0089 shows: the list holds the others too, marked.
    private func shown(_ list: AgyModelList) -> [CatalogModel] { ModelUsefulness.shown(list.models, onlyUseful: true) }

    private static func fixture(_ name: String) throws -> String {
        String(decoding: try Data(contentsOf: fixtures.appending(path: name)), as: UTF8.self)
    }

    private func recordedModels() async throws -> AgyModelList { try await models(Self.fixture("model-list.json")) }

    @Test
    func
        `the recorded list keeps the fifteen chat models: the server's groups, then command and tiered models, then the rest by id`()
        async throws
    {
        let list = try await recordedModels()
        // Groups: the Argon, Flash 3.8, Claude and GPT-OSS agent models. Then the command model, the tiered models by tier name.
        // Then the remaining thinking models, by id.
        let expected = """
            gemini-4-argon-medium gemini-4-argon-high gemini-4-argon-low gemini-3.8-flash-high gemini-3.8-flash-medium \
            gemini-3.8-flash-low claude-opus-5-5-low claude-opus-5-5-medium claude-opus-5-5-high claude-sonnet-5-5-low \
            claude-sonnet-5-5-medium claude-sonnet-5-5-high gpt-oss-120b-medium gemini-3-flash gemini-3.8-flash-tiered \
            gemini-3.5-flash-lite gemini-2.5-flash gemini-2.5-flash-lite gemini-2.5-flash-thinking gemini-2.5-pro \
            gemini-3.1-flash-lite
            """
        let names: [String] = expected.split(separator: " ").map { String($0) }  // apart: slow to type-check in #expect
        #expect(shown(list).map(\.id) == names)
    }

    @Test func `image and internal entries are kept, marked, and hidden by the filter`() async throws {
        let list = try await recordedModels()
        let marks = Dictionary(uniqueKeysWithValues: list.models.map { ($0.id, $0.unsuitable) })
        #expect(marks["gemini-3.1-flash-image"] == "image generation")
        #expect(marks["chat_20706"] == "tab completion" && marks["chat_23310"] == "tab completion")
        #expect(marks["tab_flash_lite_preview"] == "not offered for chat", "named in no group and not a thinking model")
        #expect(shown(list).allSatisfy { $0.unsuitable == nil } && shown(list).count < list.models.count)
        #expect(ModelUsefulness.shown(list.models, onlyUseful: false).count == list.models.count)
    }

    @Test func `limits come from the server and an unreported limit stays unknown`() async throws {
        let byID = Dictionary(uniqueKeysWithValues: try await recordedModels().models.map { ($0.id, $0) })
        #expect(byID["claude-opus-5-5-low"]?.contextWindow == 1_000_000)
        #expect(byID["claude-opus-5-5-low"]?.maxOutputTokens == 128_000)
        #expect(byID["gpt-oss-120b-medium"]?.contextWindow == 131_072)
        #expect(byID["gemini-3.1-flash-lite"]?.maxOutputTokens == 65_535)
        #expect(byID["gemini-3.8-flash-tiered"]?.maxOutputTokens == 65_536)
        #expect(byID["claude-opus-5-5-low"]?.supportsThinking == true)
        #expect(byID["gemini-3-flash"]?.reasoningLevels.isEmpty == true, "effort is in the id, not a level list")
    }

    @Test func `the order does not depend on how the server happens to order its members`() async throws {
        let body = #"""
            {"models":{"zeta":{"supportsThinking":true},"alpha":{"supportsThinking":true},"mid":{"supportsThinking":true},
            "t2":{"maxTokens":1},"t1":{"maxTokens":1}},
            "tieredModelIds":{"pro":["t2"],"flash":["t1"]}}
            """#
        #expect(shown(try await models(body)).map(\.id) == ["t1", "t2", "alpha", "mid", "zeta"])
    }

    @Test func `the server's own default is reported when it is listed, and only then`() async throws {
        #expect(try await recordedModels().defaultModelID == "gemini-4-argon-medium")
        let hidden =
            #"{"models":{"a":{"supportsThinking":true},"chat_1":{"isInternal":true,"maxTokens":9}},"defaultAgentModelId":"chat_1"}"#
        let list = try await models(hidden)
        #expect(shown(list).map(\.id) == ["a"] && list.defaultModelID == nil)
        let missing = try await models(#"{"models":{"a":{"supportsThinking":true}},"defaultAgentModelId":"zzz"}"#)
        #expect(missing.defaultModelID == nil)
    }

    @Test func `a role beats a capability, and internal beats everything`() async throws {
        let body = #"""
            {"models":{"t":{"supportsThinking":true},"i":{"supportsThinking":true},"a":{"supportsThinking":true},
            "x":{"supportsThinking":true,"isInternal":true},"ok":{"supportsThinking":true}},
            "tabModelIds":["t"],"imageGenerationModelIds":["i"],"audioTranscriptionModelIds":["a"],
            "agentModelSorts":[{"groups":[{"modelIds":["x","t"]}]}]}
            """#
        #expect(shown(try await models(body)).map(\.id) == ["ok"])
    }

    @Test func `a named entry that reports no thinking still counts, a bare one does not`() async throws {
        let body = #"""
            {"models":{"named":{"maxTokens":10},"bare":{"maxTokens":10},"cmd":{"maxTokens":10},"tier":{"maxTokens":10}},
            "agentModelSorts":[{"groups":[{"modelIds":["named"]}]}],"commandModelIds":["cmd"],
            "tieredModelIds":{"pro":["tier"]}}
            """#
        #expect(shown(try await models(body)).map(\.id) == ["named", "cmd", "tier"])
    }

    @Test func `ids that name nothing, repeat, or are not plain are dropped, one at a time`() async throws {
        let body = #"""
            {"models":{"good":{"supportsThinking":true},"bad id":{"supportsThinking":true},"../x":{"supportsThinking":true},
            "":{"supportsThinking":true},"notobject":7},
            "agentModelSorts":[{"groups":[{"modelIds":["good","good","ghost","bad id","../x","","notobject",5,null]}]}]}
            """#
        #expect(shown(try await models(body)).map(\.id) == ["good"])
    }

    @Test func `limits that are not positive whole numbers are unknown, not zero or negative`() async throws {
        let body =
            #"{"models":{"a":{"supportsThinking":true,"maxTokens":0,"maxOutputTokens":-5},"b":{"supportsThinking":true,"maxTokens":1.5,"maxOutputTokens":"9"},"c":{"supportsThinking":true,"maxTokens":99999999999999999999}}}"#
        let list = try await models(body)
        #expect(list.models.map(\.id) == ["a", "b", "c"])
        #expect(list.models.allSatisfy { $0.contextWindow == nil && $0.maxOutputTokens == nil })
    }

    @Test func `a list with no usable model, or not shaped like one, is an error and not an empty list`() async {
        await #expect(throws: ModelCatalogError.noModels) { try await models(#"{"models":{}}"#) }
        await #expect(throws: ModelCatalogError.noModels) {
            try await models(#"{"models":{"chat_1":{"isInternal":true}}}"#)
        }
        for body in ["", "[]", "{broken", #"{"models":[]}"#, #"{"models":7}"#, #"{"nothing":1}"#] {
            await #expect(throws: ModelCatalogError.invalidResponse, "\(body)") { try await models(body) }
        }
        await #expect(throws: ModelCatalogError.refused(status: 401)) { try await models("{}", status: 401) }
    }

    @Test func `the model request carries the project in a body that cannot be broken out of`() async throws {
        let transport = SequencedTransport([.json(200, try Self.fixture("model-list.json"))])
        _ = try await AgyCloudClient(transport: transport)
            .models(accessToken: "access-test", project: "ask-test-project-1")
        let request = try #require(transport.sent.first)
        #expect(
            request.url.absoluteString == "https://daily-cloudcode-pa.googleapis.com/v1internal:fetchAvailableModels"
        )
        #expect(try AemiJSON.parse(request.body).root["project"].string == "ask-test-project-1")
        let untouched = SequencedTransport([.json(200, try Self.fixture("model-list.json"))])
        await #expect(throws: AgyCloudError.invalidResponse) {
            try await AgyCloudClient(transport: untouched).models(accessToken: "t", project: "x\",\"y\":\"z")
        }
        #expect(untouched.sent.isEmpty, "a bad project is refused before anything is sent")
    }
}
