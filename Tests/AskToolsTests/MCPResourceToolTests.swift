import AskAI
import AskAgentCore
import AskMCP
import Foundation
import Testing

@testable import AskTools

/// Roadmap 0067, phase 5: `server_resource` lets the model list and read what servers offer as resources. It is offered only while a
/// connected server has resources, and reads under the same rules as a server's tools.
@Suite("The model lists and reads servers' resources", .timeLimit(.minutes(1)))
struct MCPResourceToolTests {
    private let world = MCPWorld()

    private func docs(read: @escaping @Sendable (String) -> String = { _ in "[]" }) -> FakeMCPServer {
        let fake = FakeMCPServer(tools: ["search"])
        fake.serveResources(
            .init(
                list: #"[{"uri":"docs://framework/swiftui","name":"SwiftUI","description":"its topic tree"}]"#,
                templates: #"[{"uriTemplate":"docs://doc/{+key}","name":"doc","description":"a page by key"}]"#,
                read: read
            )
        )
        return fake
    }

    private func started(_ fakes: [String: FakeMCPServer]) async -> MCPHost {
        let host = world.host(fakes.keys.sorted().map { world.setting($0) }, fakes)
        host.start()
        await host.waitUntilSettled()
        return host
    }

    @Test func `it is offered only while a connected server has resources`() async throws {
        let plain = await started(["plain": FakeMCPServer(tools: ["a"])])
        #expect(!world.offered.contains("server_resource"))
        await plain.stop()
        let fake = docs()
        let host = world.host([world.setting("docs")], ["docs": fake])
        var notices = host.notices.makeAsyncIterator()
        host.start()
        await host.waitUntilSettled()
        _ = await notices.next()
        #expect(world.offered.contains("server_resource"))
        fake.end()
        #expect(await notices.next()?.contains("went away") == true)
        #expect(!world.offered.contains("server_resource"))
        await host.stop()
    }

    @Test func `a server alone lists its resources and templates`() async throws {
        let host = await started(["docs": docs()])
        let output = try await world.call("server_resource", #"{"server":"docs"}"#)
        #expect(!output.isError)
        #expect(output.content.contains("docs://framework/swiftui") && output.content.contains("SwiftUI"))
        #expect(output.content.contains("its topic tree"))
        #expect(output.content.contains("docs://doc/{+key}") && output.content.contains("a page by key"))
        await host.stop()
    }

    @Test func `a URI is read, its text given whole and bytes named`() async throws {
        let fake = docs { uri in
            ##"[{"uri":"\##(uri)","mimeType":"text/markdown","text":"# View"},{"uri":"\##(uri).bin","mimeType":"application/octet-stream","blob":"AAEC"}]"##
        }
        let host = await started(["docs": fake])
        let output = try await world.call("server_resource", #"{"server":"docs","uri":"docs://doc/swiftui/view"}"#)
        #expect(fake.readURIs == ["docs://doc/swiftui/view"])
        #expect(!output.isError && output.content.contains("# View"))
        #expect(output.content.contains("docs://doc/swiftui/view.bin") && !output.content.contains("AAEC"))
        await host.stop()
    }

    @Test func `a picture among the bytes is shown, as a tool's would be`() async throws {
        let pixel = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
        let fake = docs { uri in #"[{"uri":"\#(uri)","mimeType":"image/png","blob":"\#(pixel)"}]"# }
        let host = await started(["docs": fake])
        let output = try await world.call("server_resource", #"{"server":"docs","uri":"docs://sf-symbol/star.png"}"#)
        #expect(!output.isError && output.images.count == 1 && !output.content.contains(pixel))
        await host.stop()
    }

    @Test func `a server without resources is an error that names the ones with them`() async throws {
        let host = await started(["docs": docs(), "plain": FakeMCPServer(tools: ["a"])])
        let output = try await world.call("server_resource", #"{"server":"plain"}"#)
        #expect(output.isError && output.content.contains("docs"))
        let missing = try await world.call("server_resource", "{}")
        #expect(missing.isError)
        await host.stop()
    }

    @Test func `a narrowed session is refused, because a server is outside the sandbox`() async throws {
        let fake = docs { _ in #"[{"uri":"x","text":"t"}]"# }
        let host = await started(["docs": fake])
        let narrowing = SessionNarrowing()
        narrowing.policy = SandboxPolicy(network: .none)
        let narrowed = ToolContext(workingDirectory: "/tmp", sandbox: .unrestricted, narrowing: narrowing)
        let output = try await world.call("server_resource", #"{"server":"docs","uri":"x"}"#, in: narrowed)
        #expect(output.isError && output.content.contains("sandbox") && fake.readURIs.isEmpty)
        await host.stop()
    }

    @Test func `a long listing is cut, and says how many more there are`() async throws {
        let many = (0 ..< 300).map { #"{"uri":"docs://r/\#($0)","name":"R\#($0)"}"# }.joined(separator: ",")
        let fake = FakeMCPServer(tools: [])
        fake.serveResources(.init(list: "[\(many)]", templates: "[]", read: { _ in "[]" }))
        let host = await started(["docs": fake])
        let output = try await world.call("server_resource", #"{"server":"docs"}"#)
        #expect(output.content.contains("docs://r/0") && !output.content.contains("docs://r/299"))
        #expect(output.content.contains("more"))
        await host.stop()
    }
}
