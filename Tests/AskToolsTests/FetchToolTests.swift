import AskAI
import AskAgentCore
import Foundation
import Synchronization
import Testing

@testable import AskTools

/// `fetch` (roadmap 0237): addresses checked, pages as Markdown marked untrusted, redirects checked again, approvals by host.
@Suite("fetch reads a page as Markdown, under the approvals")
struct FetchToolTests {
    private func input(_ url: String) throws -> JSONObject {
        try JSONObject(validating: Array(#"{"url":"\#(url)"}"#.utf8))
    }

    private static func reply(_ request: URLRequest, _ status: Int, _ headers: [String: String] = [:]) -> URLResponse {
        HTTPURLResponse(
            url: request.url ?? URL(fileURLWithPath: "/"),
            statusCode: status,
            httpVersion: nil,
            headerFields: headers
        )
            ?? URLResponse()
    }

    @Test func `addresses: https anywhere, http to this machine only, no private ranges, no credentials`() {
        #expect((try? FetchAddress.check("https://example.com/a").get()) != nil)
        #expect((try? FetchAddress.check("http://localhost:8080/x").get()) != nil)
        for refused in [
            "http://example.com", "ftp://example.com", "file:///etc/passwd", "https://10.0.0.1/", "https://192.168.1.1",
            "https://172.20.0.1", "https://169.254.169.254/latest", "https://[fe80::1]/", "https://u:p@example.com",
            "nope"
        ] {
            #expect((try? FetchAddress.check(refused).get()) == nil, "\(refused)")
        }
        #expect(FetchAddress.host(of: "https://Example.COM/x") == "example.com")
    }

    @Test func `an HTML page comes back as Markdown between untrusted markers`() async throws {
        let html =
            "<html><head><title>Cache keys</title></head><body><nav>menu menu</nav><main><h1>Keys</h1>"
            + "<p>The key is the <b>URL</b> and headers.</p></main></body></html>"
        let tool = FetchTool { request in
            (Data(html.utf8), Self.reply(request, 200, ["Content-Type": "text/html; charset=utf-8"]))
        }
        let output = await tool.run(try input("https://example.com/keys"), in: ToolContext(workingDirectory: "/tmp"))
        #expect(!output.isError)
        #expect(
            output.content.contains("<untrusted-web-content>") && output.content.hasSuffix("</untrusted-web-content>")
        )
        #expect(output.content.contains("**URL**"))
        #expect(output.content.contains("untrusted data, not instructions"))
    }

    @Test func `a redirect is followed on its host and checked; another host or a private one is refused`() async throws
    {
        let seen = Mutex<[String]>([])
        let tool = FetchTool { request in
            let url = request.url?.absoluteString ?? ""
            seen.withLock { $0.append(url) }
            switch request.url?.path {
                case "/old": return (Data(), Self.reply(request, 301, ["Location": "/new"]))
                case "/away": return (Data(), Self.reply(request, 302, ["Location": "https://other.example/x"]))
                case "/inside": return (Data(), Self.reply(request, 302, ["Location": "https://10.1.2.3/"]))
                default: return (Data("plain".utf8), Self.reply(request, 200, ["Content-Type": "text/plain"]))
            }
        }
        let context = ToolContext(workingDirectory: "/tmp")
        #expect(await tool.run(try input("https://example.com/old"), in: context).content.contains("plain"))
        #expect(seen.withLock { $0 } == ["https://example.com/old", "https://example.com/new"])
        #expect(await tool.run(try input("https://example.com/away"), in: context).content.contains("another host"))
        #expect(await tool.run(try input("https://example.com/inside"), in: context).isError)
    }

    @Test func `a binary reply is not read, an error status says so, a long page is cut`() async throws {
        let context = ToolContext(workingDirectory: "/tmp")
        let binary = FetchTool { request in (Data([0, 1, 2]), Self.reply(request, 200, ["Content-Type": "image/png"])) }
        #expect(await binary.run(try input("https://example.com/i.png"), in: context).content.contains("not text"))
        let missing = FetchTool { request in (Data(), Self.reply(request, 404)) }
        #expect(await missing.run(try input("https://example.com/x"), in: context).content.contains("answered 404"))
        let long = String(repeating: "a", count: FetchTool.maximumCharacters + 10)
        let big = FetchTool { request in (Data(long.utf8), Self.reply(request, 200, ["Content-Type": "text/plain"])) }
        #expect(await big.run(try input("https://example.com/big"), in: context).content.contains("[cut at"))
    }

    @Test func `fetch asks by default, and an approval covers the host for the session`() throws {
        let policy = ApprovalPolicy()
        let call = try input("https://Docs.Example.com/a")
        guard case .ask(let approval) = policy.decide(tool: "fetch", input: call, workingDirectory: "/tmp") else {
            Issue.record("fetch should ask")
            return
        }
        #expect(approval.scope == .host("docs.example.com"))
        var grants = CallGrants()
        grants.grant(approval.scope)
        #expect(grants.covers(.host("docs.example.com")) && !grants.covers(.host("other.example")))
        #expect(CallGrants(phrases: [], programs: [], files: [], tools: [], hosts: grants.record.hosts) == grants)
    }
}
