internal import Foundation
internal import Testing

@testable import AskAI

/// What the callback listener makes of the bytes a browser sends, with no socket involved. The rules are the ones
/// pi-integrations' loopback server pins: each is an attack a local listener is open to.
@Suite("A callback request is read strictly: one GET, a host that is this machine, one value per parameter")
struct LoopbackRequestTests {
    private func parse(_ text: String) -> LoopbackRequest? { LoopbackRequest(parsing: Array(text.utf8)) }

    @Test func `a browser's callback is read into its path, query and host`() throws {
        let request = try #require(
            parse("GET /auth/callback?code=abc%20d&state=s1 HTTP/1.1\r\nHost: localhost:1455\r\nAccept: */*\r\n\r\n"))
        #expect(request.method == "GET")
        #expect(request.path == "/auth/callback")
        #expect(request.value(of: "code") == "abc d")
        #expect(request.value(of: "state") == "s1")
        #expect(request.host == "localhost:1455")
    }

    @Test func `a header name is matched without regard to case`() throws {
        #expect(try #require(parse("GET / HTTP/1.1\r\nHOST: 127.0.0.1:9\r\n\r\n")).host == "127.0.0.1:9")
    }

    @Test func `a parameter given twice has no value, so a second code cannot override the first`() throws {
        let request = try #require(parse("GET /p?code=a&code=b&state=s HTTP/1.1\r\nHost: x\r\n\r\n"))
        #expect(request.value(of: "code") == nil)
        #expect(request.value(of: "state") == "s")
    }

    @Test(arguments: [
        "", "GET", "GET /p", "GET /p HTTP/2.0\r\nHost: x\r\n\r\n", "GET /p FTP/1.1\r\nHost: x\r\n\r\n",
        "GET p HTTP/1.1\r\nHost: x\r\n\r\n", "GET http://evil.example/p HTTP/1.1\r\nHost: x\r\n\r\n",
        "GET /p HTTP/1.1\r\nHost x\r\n\r\n", "GET /p HTTP/1.1\r\nHost: x\r\nHost: y\r\n\r\n", "\u{0}\u{1}\u{2}"
    ])
    func `anything that is not a plain origin-form request is refused`(text: String) {
        #expect(parse(text) == nil, "\(text.debugDescription)")
    }

    @Test func `a request with no host header has none, and the listener will refuse it`() throws {
        #expect(try #require(parse("GET /p HTTP/1.0\r\n\r\n")).host == nil)
    }

    @Test func `a request longer than the limit is refused, not buffered`() {
        let padding = String(repeating: "a", count: LoopbackRequest.limit)
        #expect(parse("GET /p?x=\(padding) HTTP/1.1\r\nHost: x\r\n\r\n") == nil)
    }
}
