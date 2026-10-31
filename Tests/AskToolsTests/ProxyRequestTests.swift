internal import Testing

@testable import AskTools

/// What the provider proxy makes of a request head (roadmap 0021): a `CONNECT host:port` tunnel is the only request it serves, and only
/// to a host and port it allows; everything else is refused with a status the client can show.
@Suite("The provider proxy reads a request")
struct ProxyRequestTests {
    private let allowed: Set<ProxyRequest.Target> = [.init(host: "api.anthropic.com", port: 443)]

    @Test func `a CONNECT to an allowed host is a tunnel to it`() {
        let head = "CONNECT api.anthropic.com:443 HTTP/1.1\r\nHost: api.anthropic.com:443\r\n\r\n"
        #expect(ProxyRequest.decide(head, allowing: allowed) == .tunnel(.init(host: "api.anthropic.com", port: 443)))
    }

    @Test func `host names compare without case, and a trailing dot is the same name`() {
        #expect(
            ProxyRequest.decide("CONNECT API.Anthropic.COM.:443 HTTP/1.1\r\n\r\n", allowing: allowed)
                == .tunnel(.init(host: "api.anthropic.com", port: 443)))
    }

    @Test func `another host, or another port of an allowed host, is refused with 403`() {
        guard
            case .refuse(let status, _) = ProxyRequest.decide(
                "CONNECT example.com:443 HTTP/1.1\r\n\r\n", allowing: allowed)
        else {
            Issue.record("example.com was let through")
            return
        }
        #expect(status == 403)
        guard
            case .refuse(403, _) = ProxyRequest.decide(
                "CONNECT api.anthropic.com:22 HTTP/1.1\r\n\r\n", allowing: allowed)
        else {
            Issue.record("port 22 of an allowed host was let through")
            return
        }
    }

    @Test func `a bracketed IPv6 address is read without its brackets`() {
        let target: Set<ProxyRequest.Target> = [.init(host: "::1", port: 8443)]
        #expect(
            ProxyRequest.decide("CONNECT [::1]:8443 HTTP/1.1\r\n\r\n", allowing: target)
                == .tunnel(.init(host: "::1", port: 8443)))
    }

    @Test func `a plain HTTP request is refused with 405: only tunnels are served`() {
        guard
            case .refuse(405, _) = ProxyRequest.decide(
                "GET http://api.anthropic.com/ HTTP/1.1\r\n\r\n", allowing: allowed)
        else {
            Issue.record("a GET was not refused with 405")
            return
        }
    }

    @Test(arguments: [
        "CONNECT api.anthropic.com HTTP/1.1\r\n\r\n", "CONNECT :443 HTTP/1.1\r\n\r\n",
        "CONNECT a:99999 HTTP/1.1\r\n\r\n",
        "CONNECT a:443\r\n\r\n", "", "\u{0}\u{1}"
    ])
    func `a malformed request is refused with 400`(head: String) {
        guard case .refuse(400, _) = ProxyRequest.decide(head, allowing: allowed) else {
            Issue.record("\(head.debugDescription) was not refused with 400")
            return
        }
    }

    @Test func `a target is read from a URL's host and port, 443 for https when none is written`() {
        #expect(
            ProxyRequest.Target(url: "https://api.anthropic.com/v1/messages")
                == .init(host: "api.anthropic.com", port: 443))
        #expect(ProxyRequest.Target(url: "https://Example.test:8443/v1") == .init(host: "example.test", port: 8443))
        #expect(ProxyRequest.Target(url: "http://127.0.0.1:11434/v1") == .init(host: "127.0.0.1", port: 11434))
        #expect(ProxyRequest.Target(url: "not a url") == nil)
    }
}
