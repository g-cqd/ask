extension GatewayServer {
    func serveController(_ stream: TCPStream, access: AccessVerifier, shell: GatewayShellFiles) async {
        guard let opening = await Self.readOpening(from: stream) else {
            await stream.close()
            return
        }
        switch opening {
            case .failure(.status(let status)):
                try? await stream.send(GatewayShellFiles.http(status: status))
                await stream.close()
            case .success(.http(let method, let path, let headers)):
                guard await access.allows(headers: headers) else {
                    try? await stream.send(GatewayShellFiles.http(status: "403 Forbidden"))
                    await stream.close()
                    return
                }
                try? await stream.send(shell.response(method: method, path: path))
                await stream.close()
            case .success(.webSocket(let handshake, let leftover)):
                guard handshake.path == "/socket" else {
                    try? await stream.send(GatewayShellFiles.http(status: "404 Not Found"))
                    await stream.close()
                    return
                }
                guard await access.allows(headers: handshake.headers) else {
                    try? await stream.send(GatewayShellFiles.http(status: "403 Forbidden"))
                    await stream.close()
                    return
                }
                guard (try? await stream.send(handshake.answer)) != nil else {
                    await stream.close()
                    return
                }
                await runWebSocket(stream, leftover: leftover)
        }
    }

    private func runWebSocket(_ stream: TCPStream, leftover: [UInt8]) async {
        let id = allocate(.controller(stream))
        relay.controllerConnected(id)
        var reader = WebSocketFrames()
        var nextChunk: [UInt8]? = leftover.isEmpty ? nil : leftover
        loop: while true {
            let chunk: [UInt8]
            if let buffered = nextChunk.take() {
                chunk = buffered
            } else {
                guard let read = try? await stream.receive() else { break }
                chunk = read
            }
            let incoming: [WebSocketFrames.Incoming]
            do { incoming = try reader.read(chunk) } catch {
                try? await stream.send(WebSocketFrames.close(error.status))
                break
            }
            for message in incoming {
                switch message {
                    case .binary(let payload):
                        guard let frame = try? RelayFrame(parsing: payload) else {
                            try? await stream.send(WebSocketFrames.close(1_002))
                            break loop
                        }
                        await dispatch(relay.receive(frame, on: id))
                    case .ping(let payload):
                        try? await stream.send(WebSocketFrames.pong(payload))
                    case .pong:
                        continue
                    case .close(let code):
                        try? await stream.send(WebSocketFrames.close(code ?? 1_000))
                        break loop
                }
            }
        }
        await dropPeer(id)
    }

    private enum OpeningError: Error {
        case status(String)
    }

    private static func readOpening(from stream: TCPStream) async -> Result<ControllerHTTPRequest.Kind, OpeningError>? {
        var buffer: [UInt8] = []
        while let piece = try? await stream.receive() {
            buffer += piece
            do {
                return .success(try ControllerHTTPRequest.parse(buffer))
            } catch .incomplete {
                continue
            } catch .tooLarge {
                return .failure(.status("431 Request Header Fields Too Large"))
            } catch .methodNotAllowed {
                return .failure(.status("405 Method Not Allowed"))
            } catch .badWebSocket(.wrongVersion) {
                return .failure(.status("426 Upgrade Required"))
            } catch {
                return .failure(.status("400 Bad Request"))
            }
        }
        return nil
    }
}
