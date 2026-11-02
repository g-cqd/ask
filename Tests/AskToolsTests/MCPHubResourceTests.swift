import AskAI
import AskAgentCore
import AskMCP
import Foundation
import Testing

@testable import AskTools

/// Roadmap 0067: what the person names as `@server:uri` is read from the server when the message is sent and attached after it, and the
/// `@server:` picker lists what a server has.
@Suite(
    "A message's @server:uri is read and attached, and a server's resources are listed for the picker",
    .timeLimit(.minutes(1))
)
struct MCPHubResourceTests {
    private func hub(_ fakes: [String: FakeMCPServer]) async -> MCPHub {
        let hub = MCPHub(environment: [:]) { server, _, _ in
            guard let fake = fakes[server.name] else { throw MCPError.refusedEndpoint("no such fake") }
            return fake
        }
        hub.apply(fakes.keys.sorted().map { MCPServerSetting(name: $0, command: "x") })
        await hub.waitUntilSettled()
        return hub
    }

    private func docs(subscribable: Bool = false) -> FakeMCPServer {
        let fake = FakeMCPServer(tools: ["search"])
        fake.serveResources(
            .init(
                list: #"[{"uri":"docs://a","name":"A"},{"uri":"docs://b","name":"b","title":"The B"}]"#,
                templates:
                    #"[{"uriTemplate":"docs://page/{+key}","name":"page"},{"uriTemplate":"docs://all","name":"all"}]"#,
                read: { uri in
                    uri == "docs://bin"
                        ? #"[{"uri":"docs://bin","mimeType":"image/png","blob":"AAEC"}]"#
                        : #"[{"uri":"\#(uri)","text":"text of \#(uri)"}]"#
                },
                subscribable: subscribable
            )
        )
        return fake
    }

    @Test func `only servers with resources are offered to the picker, with each resource's URI and name`() async throws
    {
        let hub = await hub(["docs": docs(), "plain": FakeMCPServer(tools: ["a"])])
        #expect(hub.resourceServers == ["docs"])
        let listed = try #require(await hub.listedResources(of: "docs"))
        #expect(listed.map(\.uri) == ["docs://a", "docs://b"] && listed.map(\.name) == ["A", "The B"])
        #expect(await hub.listedResources(of: "plain") == nil)
        hub.apply([])
        await hub.waitUntilSettled()
    }

    @Test func `each named resource is read once and attached in order, bytes named and not sent`() async throws {
        let fake = docs()
        let hub = await hub(["docs": fake])
        let sent = await hub.attachResources("see @docs:docs://b and @docs:docs://bin, @docs:docs://b @plain:x://y")
        #expect(fake.readURIs == ["docs://b", "docs://bin"])
        #expect(
            sent == """
                see @docs:docs://b and @docs:docs://bin, @docs:docs://b @plain:x://y

                --- resource docs:docs://b ---
                text of docs://b
                --- end of resource ---

                --- resource docs:docs://bin ---
                [docs://bin (image/png): not text, not attached]
                --- end of resource ---
                """
        )
        #expect(await hub.attachResources("no references here") == "no references here")
        hub.apply([])
        await hub.waitUntilSettled()
    }

    @Test func `a read that fails says why, in the place of the text`() async throws {
        let fake = docs()
        fake.serveResources(.init(list: "[]", templates: "[]", read: { _ in "7" }))
        let hub = await hub(["docs": fake])
        let sent = await hub.attachResources("@docs:docs://gone")
        #expect(sent.contains("--- resource docs:docs://gone ---\n[the server returned nothing for it]"))
        hub.apply([])
        await hub.waitUntilSettled()
    }

    @Test func `a server's templates are listed for the picker too, with the part to type before the first brace`()
        async throws
    {
        let hub = await hub(["docs": docs(), "plain": FakeMCPServer(tools: ["a"])])
        let templates = try #require(await hub.listedTemplates(of: "docs"))
        #expect(templates.map(\.template) == ["docs://page/{+key}", "docs://all"])
        #expect(templates.map(\.name) == ["page", "all"])
        #expect(await hub.listedTemplates(of: "plain") == nil)
        #expect(MCPHub.typedPart(of: "docs://page/{+key}") == "docs://page/")
        #expect(MCPHub.typedPart(of: "apple-docs://doc/{+key}{?lang}") == "apple-docs://doc/")
        #expect(MCPHub.typedPart(of: "docs://all") == "docs://all", "no variable: the whole URI")
    }

    /// The owner's choice (2026-11-02): each resource a message attaches is followed, where the server can, and the person is told when
    /// one changes; a server's changed list makes the picker ask again.
    @Test func `an attached resource is subscribed to once, where the server can`() async throws {
        let subscribing = docs(subscribable: true)
        let plain = docs()
        let hub = await hub(["docs": subscribing, "other": plain])
        _ = await hub.attachResources("see @docs:docs://a and @other:docs://a")
        _ = await hub.attachResources("again @docs:docs://a, and @docs:docs://b")
        #expect(subscribing.subscriptions == ["docs://a", "docs://b"])
        #expect(plain.subscriptions.isEmpty, "a server without subscribe is not asked")
    }

    @Test func `a change to a subscribed resource is told to the person, and one never attached is not`() async throws {
        let fake = docs(subscribable: true)
        let hub = await hub(["docs": fake])
        _ = await hub.attachResources("see @docs:docs://a")
        fake.announceUpdate("docs://never")
        fake.announceUpdate("docs://a")
        var told: String?
        for await line in hub.notices where line.contains("changed") {
            told = line
            break
        }
        #expect(told?.contains("@docs:docs://a") == true && told?.contains("never") == false)
    }

    @Test func `a server's changed resource list is passed on, by its name`() async throws {
        let fake = docs()
        let hub = await hub(["docs": fake])
        fake.announceResourceListChange()
        var changed: String?
        for await server in hub.resourceListChanges {
            changed = server
            break
        }
        #expect(changed == "docs")
    }
}
