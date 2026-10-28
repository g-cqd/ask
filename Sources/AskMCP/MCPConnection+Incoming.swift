internal import AemiJSON
internal import Synchronization

extension MCPConnection {
    /// Starts the loop that takes messages in from the server as they come. Messages out are sent by whoever has one (`+Outbound`).
    func launchLoops() {
        Task { [self] in
            for await line in transport.incoming { handle(line) }
            shutdown()
        }
    }

    /// One message from the server.
    func handle(_ line: [UInt8]) {
        switch MCPEnvelope.parse(line) {
            case .response(let id, let outcome): resolve(id, outcome)
            case .request(let id, let method, _): answer(method, id: id)
            case .notification(let method, let params): notice(method, params)
            case .malformed(let what): eventSink.yield(.malformed(what))
        }
    }

    /// A request from the server. No capability was declared, so the only one expected is `ping`; anything else is refused as unknown.
    private func answer(_ method: String, id: [UInt8]) {
        if method == "ping" {
            enqueue(MCPWire.result(id: id))
        } else {
            enqueue(MCPWire.failure(id: id, code: -32601, message: "Method not found"))
        }
    }

    /// A notification from the server.
    private func notice(_ method: String, _ params: [UInt8]?) {
        let root = params.flatMap {
            try? AemiJSON.parse($0, options: JSONParseOptions(recordsContainerSpans: true)).root
        }
        switch method {
            case "notifications/tools/list_changed": eventSink.yield(.toolsChanged)
            case "notifications/message":
                guard let root else { return }
                let data = root["data"]
                let text = data.string ?? data.withRawJSONBytes { String(decoding: $0, as: UTF8.self) } ?? ""
                eventSink.yield(.log(level: root["level"].string, text: text))
            case "notifications/progress":
                guard let root, let token = Self.token(root["progressToken"]) else { return }
                let handler = state.withLock { $0.progress[token] }
                handler?(
                    MCPProgress(
                        progress: root["progress"].double ?? 0, total: root["total"].double,
                        message: root["message"].string))
            default: break
        }
    }

    /// A progress token, which a server may write as a string or as a number.
    private static func token(_ value: JSON) -> String? {
        value.string ?? value.int.map(String.init)
    }
}
