import Foundation
import Synchronization
import Testing

@testable import AskAI

/// The URLSession transport, driven through a URLProtocol stub so no test touches the network.
@Suite("The URLSession transport streams bodies and reports failures")
struct HTTPTransportTests {
    private let transport = URLSessionTransport(session: StubProtocol.session)

    private func request(_ name: String) -> HTTPRequest {
        HTTPRequest(
            url: URL(string: "https://stub.invalid/\(name)")!, method: "POST",
            headers: [("content-type", "application/json"), ("x-app", "cli")], body: Array(#"{"a":1}"#.utf8))
    }

    @Test func `the status arrives first and the body follows in order`() async throws {
        let request = request(#function)
        StubProtocol.script(request.url, Script(status: 200, chunks: ["data: one\n\n", "data: two\n\n"], failure: nil))
        let response = try await transport.send(request)
        #expect(response.status == 200)
        #expect(response.headers["content-type"] == "text/event-stream", "header names arrive lowercased")
        #expect(try await response.collect() == Array("data: one\n\ndata: two\n\n".utf8))
        let seen = try #require(StubProtocol.received(request.url))
        #expect(seen.method == "POST")
        #expect(seen.headers["x-app"] == "cli")
        #expect(seen.body == request.body)
    }

    @Test func `an error status is returned with its body, not thrown`() async throws {
        let request = request(#function)
        StubProtocol.script(request.url, Script(status: 429, chunks: [#"{"type":"error"}"#]))
        let response = try await transport.send(request)
        #expect(response.status == 429)
        #expect(try await response.collect() == Array(#"{"type":"error"}"#.utf8))
    }

    @Test func `a connection that fails before a response throws`() async {
        let request = request(#function)
        StubProtocol.script(request.url, Script(status: nil, chunks: [], failure: URLError(.cannotConnectToHost)))
        await #expect(throws: HTTPTransportError.self) { _ = try await transport.send(request) }
    }

    @Test func `a body cut mid-stream throws after what arrived`() async throws {
        let request = request(#function)
        // The failure is held until the first chunk has been received, as on a real connection. A stub that
        // fails in the same call makes URLSession drop the response it already had.
        StubProtocol.script(
            request.url, Script(status: 200, chunks: ["data: partial"], heldFailure: URLError(.networkConnectionLost)))
        let response = try await transport.send(request)
        var iterator = response.body.makeAsyncIterator()
        #expect(try await iterator.next() == Array("data: partial".utf8))
        StubProtocol.releaseFailure(request.url)
        await #expect(throws: (any Error).self) { _ = try await iterator.next() }
    }

    @Test func `collecting refuses a body over the limit`() async throws {
        let request = request(#function)
        StubProtocol.script(request.url, Script(status: 200, chunks: [String(repeating: "x", count: 64)]))
        let response = try await transport.send(request)
        await #expect(throws: HTTPTransportError.bodyTooLarge(limit: 16)) { _ = try await response.collect(limit: 16) }
    }

    struct Script: Sendable {
        var status: Int?
        var chunks: [String]
        var failure: URLError?
        /// A failure delivered only when the test calls ``StubProtocol/releaseFailure(_:)``.
        var heldFailure: URLError?
    }

    /// A loader waiting for the test to release its failure.
    struct HeldFailure: Sendable {
        let loader: StubProtocol
        let failure: URLError
    }

    struct Received: Sendable {
        var method: String
        var headers: [String: String]
        var body: [UInt8]
    }

    /// Serves scripted responses keyed by URL. State is behind a Mutex, so tests run in parallel safely.
    // SAFETY: URLProtocol is not Sendable; this subclass adds no mutable instance state, and the shared tables
    // it reads are guarded by a Mutex.
    final class StubProtocol: URLProtocol, @unchecked Sendable {
        private static let scripts = Mutex<[URL: Script]>([:])
        private static let requests = Mutex<[URL: Received]>([:])
        private static let held = Mutex<[URL: HeldFailure]>([:])

        static let session: URLSession = {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [StubProtocol.self]
            return URLSession(configuration: configuration)
        }()

        static func script(_ url: URL, _ script: Script) { scripts.withLock { $0[url] = script } }
        static func received(_ url: URL) -> Received? { requests.withLock { $0[url] } }

        /// Delivers the held failure for `url`.
        static func releaseFailure(_ url: URL) {
            guard let pending = held.withLock({ $0.removeValue(forKey: url) }) else { return }
            pending.loader.client?.urlProtocol(pending.loader, didFailWithError: pending.failure)
        }

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            guard let url = request.url, let script = Self.scripts.withLock({ $0[url] }) else { return }
            Self.requests.withLock {
                $0[url] = Received(
                    method: request.httpMethod ?? "", headers: request.allHTTPHeaderFields ?? [:],
                    body: Self.body(of: request))
            }
            if let status = script.status {
                // With no Content-Type, URLSession withholds the response until it can sniff a type from enough
                // body bytes, so a short streamed body never reaches the delegate. Real event streams declare it.
                let response = HTTPURLResponse(
                    url: url, statusCode: status, httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "text/event-stream"])!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                for chunk in script.chunks { client?.urlProtocol(self, didLoad: Data(chunk.utf8)) }
            }
            if let failure = script.heldFailure {
                let pending = HeldFailure(loader: self, failure: failure)
                Self.held.withLock { $0[url] = pending }
            } else if let failure = script.failure {
                client?.urlProtocol(self, didFailWithError: failure)
            } else {
                client?.urlProtocolDidFinishLoading(self)
            }
        }

        override func stopLoading() {}

        /// URLSession hands a stub the body as a stream, not as `httpBody`.
        private static func body(of request: URLRequest) -> [UInt8] {
            if let body = request.httpBody { return [UInt8](body) }
            guard let stream = request.httpBodyStream else { return [] }
            stream.open()
            defer { stream.close() }
            var bytes: [UInt8] = []
            var buffer = [UInt8](repeating: 0, count: 4_096)
            while true {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                bytes += buffer[..<count]
            }
            return bytes
        }
    }
}

// MARK: - Stub
