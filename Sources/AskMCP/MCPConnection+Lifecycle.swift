internal import AemiJSON
internal import Synchronization

extension MCPConnection {
    /// Opens the conversation: offers the newest protocol version, takes what the server answers if it is one this client speaks, and
    /// says it is ready.
    /// - Returns: what the server said about itself.
    /// - Throws: ``MCPError/unsupportedVersion(_:)`` (the connection is closed), the server's own refusal, or the transport's failure.
    public func start() async throws(MCPError) -> MCPServerInfo {
        try state.withLock { state throws(MCPError) in
            guard !state.begun else { throw .alreadyStarted }
            state.begun = true
        }
        launchLoops()
        let reply = try await request(
            "initialize", params: initializeParams(), timeout: startTimeout, beforeStart: true)
        guard let document = try? AemiJSON.parse(reply, options: JSONParseOptions(recordsContainerSpans: true)) else {
            await close()
            throw .malformedResponse("the answer to initialize cannot be read")
        }
        let root = document.root
        guard let version = root["protocolVersion"].string else {
            await close()
            throw .malformedResponse("the answer to initialize has no protocolVersion")
        }
        guard MCPProtocolVersion.supported.contains(version) else {
            await close()
            throw .unsupportedVersion(version)
        }
        transport.negotiated(protocolVersion: version)
        // Written now and not queued: nothing else can be queued before the connection is started, so the order is safe, and the caller
        // can rely on the server having been told when this returns.
        do { try await transport.send(MCPWire.notification(method: "notifications/initialized")) } catch {
            await close()
            throw .disconnected
        }
        state.withLock { $0.started = true }
        let tools = root["capabilities"]["tools"]
        return MCPServerInfo(
            protocolVersion: version, name: root["serverInfo"]["name"].string ?? "",
            title: root["serverInfo"]["title"].string, version: root["serverInfo"]["version"].string ?? "",
            instructions: root["instructions"].string, supportsTools: tools.isObject,
            toolsMayChange: tools["listChanged"].bool ?? false)
    }

    private func initializeParams() -> [UInt8] {
        var writer = JSONStreamWriter(options: .rfc8259)
        MCPWire.object(&writer) { body in
            MCPWire.put(&body, "protocolVersion", string: MCPProtocolVersion.offered)
            MCPWire.put(&body, "capabilities", raw: Array("{}".utf8))
            body.key("clientInfo")
            MCPWire.object(&body) { info in
                MCPWire.put(&info, "name", string: clientName)
                MCPWire.put(&info, "version", string: clientVersion)
            }
        }
        return writer.finish()
    }
}
