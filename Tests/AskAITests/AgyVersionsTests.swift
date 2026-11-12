import Foundation
import Testing

@testable import AskAI

/// Cloud Code grows its model list with the `agy` version a request names, so ask names the newest, read from the CLI's own update
/// service at most once an hour.
@Suite("Antigravity requests name the newest agy version, checked hourly")
struct AgyVersionsTests {
    private static let page = "Antigravity CLI auto updater is running! Stable Version: 1.9.2. Rolled out to 100%"

    private func source(_ transport: any HTTPTransport, timeout: Double = 2) -> (AgyVersions, URL) {
        let root = FileManager.default.temporaryDirectory.appending(path: "ask-agy-versions-\(UUID().uuidString)")
        let cache = root.appending(path: "agy-cli-version.json")
        return (AgyVersions(cache: cache, transport: transport, timeout: timeout), cache)
    }

    @Test func `with no cache the stable version is read, kept, and not read again within the hour`() async {
        let transport = CopilotTestTransport { _ in CopilotTestTransport.reply(Self.page) }
        let (versions, _) = source(transport)
        #expect(await versions.current(now: 10_000) == "1.9.2")
        #expect(await versions.current(now: 10_000 + 3_599) == "1.9.2")
        #expect(transport.requests.count == 1)
        #expect(transport.requests.first?.url == AgyVersions.service)
        _ = await versions.current(now: 10_000 + 3_600)
        #expect(transport.requests.count == 2)
    }

    @Test func `a cache dated after now is read again`() async {
        let transport = CopilotTestTransport { _ in CopilotTestTransport.reply(Self.page) }
        let (versions, _) = source(transport)
        _ = await versions.current(now: 10_000)
        _ = await versions.current(now: 9_000)
        #expect(transport.requests.count == 2)
    }

    @Test func `when the check fails the last version read stays, and it is tried again after five minutes`() async {
        let (versions, cache) = source(CopilotTestTransport { _ in CopilotTestTransport.reply(Self.page) })
        _ = await versions.current(now: 10_000)
        let failing = CopilotTestTransport { _ in CopilotTestTransport.reply("", status: 503) }
        let offline = AgyVersions(cache: cache, transport: failing)
        #expect(await offline.current(now: 20_000) == "1.9.2")
        _ = await offline.current(now: 20_000 + 299)
        #expect(failing.requests.count == 1)
        _ = await offline.current(now: 20_000 + 300)
        #expect(failing.requests.count == 2)
    }

    @Test func `with nothing read yet a failed check uses the version ask was built with`() async {
        let (versions, _) = source(CopilotTestTransport { _ in CopilotTestTransport.reply("", status: 500) })
        #expect(await versions.current(now: 10_000) == AgyVersions.known)
    }

    @Test func `a service slower than the bound does not hold the request`() async {
        let (versions, _) = source(StalledTransport(), timeout: 0.05)
        #expect(await versions.current(now: 10_000) == AgyVersions.known)
    }

    @Test(arguments: [
        "", "Stable Version: ", "Stable Version: latest", "Stable Version: 1", "Stable Version: 1.2.3.4.5",
        "Stable Version: 1234567.1", "Stable Version: .1.2", "Stable Version: 1..2", "stable version: 1.5.6"
    ])
    func `a page that does not name a plain version is not used`(page: String) async {
        let (versions, _) = source(CopilotTestTransport { _ in CopilotTestTransport.reply(page) })
        #expect(await versions.current(now: 10_000) == AgyVersions.known)
    }

    @Test func `a version is read up to the sentence's full stop`() {
        #expect(AgyVersions.stableVersion(in: Array("Stable Version: 1.5.6. Rolled".utf8)) == "1.5.6")
        #expect(AgyVersions.stableVersion(in: Array("Stable Version: 12.30".utf8)) == "12.30")
    }

    @Test func `a damaged cache is ignored, and what it held is never sent`() async throws {
        let transport = CopilotTestTransport { _ in CopilotTestTransport.reply("", status: 500) }
        let (versions, cache) = source(transport)
        try FileManager.default.createDirectory(
            at: cache.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(#"{"version":"1.2\r\nx-evil: 1","at":99999}"#.utf8).write(to: cache)
        #expect(await versions.current(now: 100_000) == AgyVersions.known)
    }

    @Test func `the cloud client names the version it is given, and the model list follows it`() async throws {
        let transport = CopilotTestTransport { request in
            request.url.path.hasSuffix("loadCodeAssist")
                ? CopilotTestTransport.reply(#"{"cloudaicompanionProject":"p-1"}"#)
                : CopilotTestTransport.reply(Self.page)
        }
        let (versions, _) = source(transport)
        _ = try await AgyCloudClient(transport: transport, versions: versions).account(accessToken: "t")
        let sent = transport.requests.first { $0.url.path.hasSuffix("loadCodeAssist") }
        let agent = sent?.headers.first { $0.name == "user-agent" }?.value
        #expect(agent == "antigravity/cli/1.9.2 ask/0 (Antigravity subscription connector)")
    }

    @Test func `a request names the version in the header and the envelope`() async throws {
        let transport = CopilotTestTransport { _ in CopilotTestTransport.reply("") }
        let request = ModelRequest(
            model: "m",
            maxTokens: 10,
            systemPrompt: ["s"],
            messages: [ModelMessage(role: .user, blocks: [.text("hi")])],
            tools: []
        )
        let stream = AgyClient(transport: transport)
            .stream(request, session: AgySession(accessToken: "a", projectID: "p"), version: "1.9.2")
        // An empty reply is a protocol error; the request is what is under test.
        do { for try await _ in stream {} } catch {}
        let sent = try #require(transport.requests.first)
        #expect(sent.headers.first { $0.name == "user-agent" }?.value.hasPrefix("antigravity/cli/1.9.2 ") == true)
        #expect(String(decoding: sent.body, as: UTF8.self).contains("antigravity/cli/1.9.2 ask/0"))
    }
}
