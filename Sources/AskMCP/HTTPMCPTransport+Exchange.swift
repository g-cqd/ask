internal import AemiJSON
internal import AskAI
internal import Foundation
internal import Synchronization

extension HTTPMCPTransport {
    /// The headers every request carries, in order.
    func requestHeaders() -> [(name: String, value: String)] {
        var all: [(name: String, value: String)] = [
            ("Content-Type", "application/json"), ("Accept", "application/json, text/event-stream"),
            ("User-Agent", userAgent)
        ]
        let (session, version) = state.withLock { ($0.sessionID, $0.protocolVersion) }
        if let session { all.append(("Mcp-Session-Id", session)) }
        if let version { all.append(("MCP-Protocol-Version", version)) }
        return all + headers
    }

    /// One message, one POST, and whatever comes back.
    func exchange(_ message: [UInt8], requestID: Int?) async {
        let request = HTTPRequest(url: url, method: "POST", headers: requestHeaders(), body: message)
        do {
            let reply = try await http.send(request)
            noteSession(reply)
            try await handle(reply, requestID: requestID)
        } catch is CancellationError {
            return
        } catch {
            fail(requestID, "the request failed: \(error)")
        }
    }

    private func noteSession(_ reply: HTTPStreamingResponse) {
        guard let session = reply.headers["mcp-session-id"], !session.isEmpty else { return }
        state.withLock { $0.sessionID = session }
    }

    private func handle(_ reply: HTTPStreamingResponse, requestID: Int?) async throws {
        let type = reply.headers["content-type"]?.lowercased() ?? ""
        switch reply.status {
            case 202, 204: return
            case 404 where state.withLock({ $0.sessionID }) != nil:
                // The server has forgotten the session: nothing more can be said on it.
                sink.finish()
            case 200 ..< 300 where type.contains("text/event-stream"):
                try await deliverEvents(reply, requestID: requestID)
            case 200 ..< 300 where type.contains("application/json"):
                try await deliverJSON(reply, requestID: requestID)
            case 200 ..< 300:
                fail(
                    requestID,
                    "the server replied with \(type.isEmpty ? "no content type" : type), which is not JSON or events")
            default:
                let body = (try? await reply.collect(limit: 1024)) ?? []
                let text = String(decoding: body.prefix(200), as: UTF8.self)
                fail(requestID, "the server answered HTTP \(reply.status)" + (text.isEmpty ? "" : ": \(text)"))
        }
    }

    private func deliverJSON(_ reply: HTTPStreamingResponse, requestID: Int?) async throws {
        let body = try await reply.collect(limit: Self.maximumMessageBytes)
        var answered = false
        if let document = try? AemiJSON.parse(body, options: JSONParseOptions(recordsContainerSpans: true)),
            document.root.isArray
        {
            document.root.forEachElement { element in
                guard let message = element.withRawJSONBytes({ Array($0) }) else { return }
                answered = deliver(message, for: requestID) || answered
            }
        } else {
            answered = deliver(body, for: requestID)
        }
        if !answered { fail(requestID, "the server replied without answering") }
    }

    func deliverEvents(_ reply: HTTPStreamingResponse, requestID: Int?) async throws {
        var decoder = SSEDecoder(limits: .init(maximumEventBytes: Self.maximumMessageBytes))
        var answered = false
        for try await chunk in reply.body {
            var events: [SSEEvent] = []
            try chunk.withUnsafeBufferPointer { try decoder.feed($0.span, into: &events) }
            for event in events where event.name == "message" {
                answered = deliver(event.data, for: requestID) || answered
            }
        }
        if !answered { fail(requestID, "the server ended its reply without answering") }
    }

    /// Hands a message to the connection.
    /// - Returns: whether it is the answer to `requestID`.
    private func deliver(_ message: [UInt8], for requestID: Int?) -> Bool {
        sink.yield(message)
        guard let requestID, case .response(let id, _) = MCPEnvelope.parse(message) else { return false }
        return id == requestID
    }

    /// Answers a request that will not be answered by the server. A notification has nobody waiting, so nothing is said.
    private func fail(_ requestID: Int?, _ reason: String) {
        guard let requestID else { return }
        sink.yield(MCPWire.failure(id: Array(String(requestID).utf8), code: Self.failureCode, message: reason))
    }

    /// Tells the server the session is over. A server may refuse (`405`), or not answer; neither matters.
    func endSession(_ session: String) async {
        var all = requestHeaders().filter { $0.name != "Content-Type" }
        all.removeAll { $0.name == "Accept" }
        let delete = Task { [http, url] in
            _ = try? await http.send(HTTPRequest(url: url, method: "DELETE", headers: all, body: []))
        }
        let stopper = Task { [clock, grace] in
            guard (try? await clock.sleep(for: grace)) != nil else { return }
            delete.cancel()
        }
        await delete.value
        stopper.cancel()
    }
}
