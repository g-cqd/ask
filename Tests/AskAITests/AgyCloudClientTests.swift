internal import AemiJSON
internal import AskCore
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
        #expect(
            header("user-agent")
                == "antigravity/cli/1.5.6 ask/\(AskVersion.current) (Antigravity subscription connector)"
        )
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
}
