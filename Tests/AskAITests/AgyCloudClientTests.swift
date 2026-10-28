internal import AemiJSON
internal import Foundation
internal import Testing

@testable import AskAI

/// Cloud Code onboarding and the model list, against bodies recorded from a real account on 2026-10-24 under ask's own identity
/// (free text, the account's address and quota figures removed, the project id replaced).
struct AgyCloudClientTests {
    private static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "Fixtures/Agy")

    private static func fixture(_ name: String) throws -> String {
        String(decoding: try Data(contentsOf: fixtures.appending(path: name)), as: UTF8.self)
    }

    private func account(_ json: String, status: Int = 200) async throws -> (AgyAccount, [HTTPRequest]) {
        let transport = SequencedTransport([.json(status, json)])
        let account = try await AgyCloudClient(transport: transport).account(accessToken: "access-test")
        return (account, transport.sent)
    }

    private func models(_ json: String, status: Int = 200) async throws -> AgyModelList {
        try await AgyCloudClient(transport: SequencedTransport([.json(status, json)]))
            .models(accessToken: "access-test", project: "ask-test-project-1")
    }

    /// The models the filter of roadmap 0089 shows: the list holds the others too, marked.
    private func shown(_ list: AgyModelList) -> [CatalogModel] { ModelUsefulness.shown(list.models, onlyUseful: true) }

    private func recordedModels() async throws -> AgyModelList { try await models(Self.fixture("model-list.json")) }

    // MARK: - Onboarding

    @Test func `onboarding reads the project and both tiers from the recorded body`() async throws {
        let (found, _) = try await account(Self.fixture("load-code-assist.json"))
        #expect(found.projectID == "ask-test-project-1")
        #expect(found.currentTierID == "free-tier")
        #expect(found.paidTierID == "g1-pro-tier")
    }

    @Test func `onboarding sends the honest identity and the access token to the one probed address`() async throws {
        let (_, sent) = try await account(Self.fixture("load-code-assist.json"))
        let request = try #require(sent.first)
        #expect(request.method == "POST")
        #expect(request.url.absoluteString == "https://daily-cloudcode-pa.googleapis.com/v1internal:loadCodeAssist")
        func header(_ name: String) -> String? { request.headers.first { $0.name == name }?.value }
        #expect(header("authorization") == "Bearer access-test")
        #expect(header("user-agent") == "antigravity/cli/1.4.0 ask/0 (Antigravity subscription connector)")
        let body = try AemiJSON.parse(request.body).root
        #expect(body["mode"].string == "FULL_ELIGIBILITY_CHECK")
        #expect(body["metadata"]["ideName"].string == "ask")
        #expect(body["metadata"]["platform"].string?.hasPrefix("DARWIN_") == true)
        #expect(!String(decoding: request.body, as: UTF8.self).contains("antigravity/cli"), "no first-party identity")
    }

    @Test func `a tier is optional, the project is not`() async throws {
        let (found, _) = try await account(#"{"cloudaicompanionProject":"p1"}"#)
        #expect(found.projectID == "p1")
        #expect(found.currentTierID == nil && found.paidTierID == nil)
    }

    @Test func `a tier id that is not a plain id is not reported, and the project is still read`() async throws {
        for bad in ["", "a b", "a/b", String(repeating: "t", count: 65), "t\\u0000", "7"] {
            let body = #"{"cloudaicompanionProject":"p1","currentTier":{"id":"\#(bad)"},"paidTier":{"id":7}}"#
            let (found, _) = try await account(body)
            #expect(found.projectID == "p1" && found.paidTierID == nil, "\(bad.debugDescription)")
            if bad != "7" { #expect(found.currentTierID == nil, "\(bad.debugDescription)") }
        }
        let (plain, _) = try await account(#"{"cloudaicompanionProject":"p1","currentTier":{"id":"A.b-c_9"}}"#)
        #expect(plain.currentTierID == "A.b-c_9")
    }

    @Test func `an account with no project says why, from the reason codes alone`() async {
        let body =
            #"{"currentTier":{"id":"free-tier","name":"x"},"ineligibleTiers":[{"reasonCode":"UNSUPPORTED_LOCATION","reasonMessage":"secret ya29.leak text"},{"reasonCode":"not a code"},{"reasonCode":"UNSUPPORTED_LOCATION"}]}"#
        await #expect(throws: AgyCloudError.noProject(reasons: ["UNSUPPORTED_LOCATION"])) { try await account(body) }
        let text = AgyCloudError.noProject(reasons: ["UNSUPPORTED_LOCATION"]).description
        #expect(text.contains("UNSUPPORTED_LOCATION") && text.contains("agy"))
    }

    @Test func `a project that is not a plain id is refused, wherever it came from`() async {
        for bad in ["", " ", "a b", "../x", "a/b", "-start", String(repeating: "a", count: 129), "p\\u0000q", "p\\\"q"]
        {
            await #expect(throws: AgyCloudError.invalidResponse, "\(bad.debugDescription)") {
                try await account(#"{"cloudaicompanionProject":"\#(bad)"}"#)
            }
        }
        for odd in ["7", "null", "[\"p\"]", "{\"id\":\"p\"}", "true"] {
            await #expect(throws: AgyCloudError.invalidResponse, "\(odd)") {
                try await account(#"{"cloudaicompanionProject":\#(odd)}"#)
            }
        }
    }

    @Test func `a body that is not an object is invalid, not an empty account`() async {
        for body in ["", "[]", "7", "{broken", "null"] {
            await #expect(throws: AgyCloudError.invalidResponse, "\(body)") { try await account(body) }
        }
    }

    @Test func `a refusal names the status and Google's status word and nothing else of the body`() async {
        let body =
            #"{"error":{"code":403,"status":"PERMISSION_DENIED","message":"token ya29.SECRET for user@example.com"}}"#
        await #expect(throws: AgyCloudError.refused(status: 403, reason: "PERMISSION_DENIED")) {
            try await account(body, status: 403)
        }
        let text = AgyCloudError.refused(status: 403, reason: "PERMISSION_DENIED").description
        #expect(text.contains("403") && text.contains("PERMISSION_DENIED") && !text.contains("ya29"))
        await #expect(throws: AgyCloudError.refused(status: 401, reason: nil)) {
            try await account("not json", status: 401)
        }
        await #expect(throws: AgyCloudError.refused(status: 500, reason: nil)) {
            try await account(#"{"error":{"status":"lower case"}}"#, status: 500)
        }
        let long = String(repeating: "A", count: 41)
        await #expect(throws: AgyCloudError.refused(status: 500, reason: nil), "a status word of 41 letters is not one")
        {
            try await account(#"{"error":{"status":"\#(long)"}}"#, status: 500)
        }
        await #expect(throws: AgyCloudError.refused(status: 500, reason: String(repeating: "A", count: 40))) {
            try await account(#"{"error":{"status":"\#(String(repeating: "A", count: 40))"}}"#, status: 500)
        }
    }

    // MARK: - The model list

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
        #expect(shown(list).map(\.id) == expected.split(separator: " ").map(String.init))
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
            request.url.absoluteString == "https://daily-cloudcode-pa.googleapis.com/v1internal:fetchAvailableModels")
        #expect(try AemiJSON.parse(request.body).root["project"].string == "ask-test-project-1")
        let untouched = SequencedTransport([.json(200, try Self.fixture("model-list.json"))])
        await #expect(throws: AgyCloudError.invalidResponse) {
            try await AgyCloudClient(transport: untouched).models(accessToken: "t", project: "x\",\"y\":\"z")
        }
        #expect(untouched.sent.isEmpty, "a bad project is refused before anything is sent")
    }
}
