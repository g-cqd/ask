internal import AemiJSON
public import AskAI
internal import Synchronization

extension MCPConnection {
    /// Every tool the server offers, following its pages.
    /// - Throws: ``MCPError/tooManyPages`` if the listing never ends, or whatever a request throws.
    public func listTools() async throws(MCPError) -> [MCPTool] {
        var tools: [MCPTool] = []
        var cursor: String?
        for _ in 0 ..< Self.maximumListPages {
            let reply = try await request(
                "tools/list", params: cursor.map(Self.cursorParams), timeout: requestTimeout)
            guard let document = try? AemiJSON.parse(reply, options: JSONParseOptions(recordsContainerSpans: true))
            else { throw .malformedResponse("the tool list cannot be read") }
            document.root["tools"]
                .forEachElement { element in
                    if let tool = MCPToolParsing.tool(element) { tools.append(tool) }
                }
            guard let next = document.root["nextCursor"].string, !next.isEmpty else { return tools }
            cursor = next
        }
        throw .tooManyPages
    }

    /// Calls a tool.
    /// - Parameters:
    ///   - name: the tool, as the server names it.
    ///   - arguments: its arguments, written to the server exactly as given.
    ///   - timeout: how long to wait for the answer, if not the connection's.
    ///   - onProgress: told how far a long call has got, if the server says.
    /// - Returns: the tool's result. A tool that ran and failed returns a result with ``MCPToolResult/isError`` set.
    /// - Throws: the server's protocol error (an unknown tool, say), a timeout, or ``MCPError/cancelled``.
    public func callTool(
        _ name: String, arguments: JSONObject, timeout: Duration? = nil,
        onProgress: (@Sendable (MCPProgress) -> Void)? = nil
    ) async throws(MCPError) -> MCPToolResult {
        let token = onProgress == nil ? nil : state.withLock { "ask-\($0.nextID + 1)" }
        if let token, let onProgress { state.withLock { $0.progress[token] = onProgress } }
        defer { if let token { state.withLock { $0.progress[token] = nil } } }
        let reply = try await request(
            "tools/call", params: Self.callParams(name: name, arguments: arguments, token: token),
            timeout: timeout ?? requestTimeout)
        guard let result = MCPToolParsing.result(reply) else {
            throw .malformedResponse("the tool result cannot be read")
        }
        return result
    }

    /// Asks the server whether it is there.
    public func ping() async throws(MCPError) {
        _ = try await request("ping", params: nil, timeout: requestTimeout)
    }

    private static func cursorParams(_ cursor: String) -> [UInt8] {
        var writer = JSONStreamWriter(options: .rfc8259)
        MCPWire.object(&writer) { MCPWire.put(&$0, "cursor", string: cursor) }
        return writer.finish()
    }

    private static func callParams(name: String, arguments: JSONObject, token: String?) -> [UInt8] {
        var writer = JSONStreamWriter(options: .rfc8259)
        MCPWire.object(&writer) { body in
            MCPWire.put(&body, "name", string: name)
            MCPWire.put(&body, "arguments", raw: arguments.bytes)
            if let token {
                body.key("_meta")
                MCPWire.object(&body) { MCPWire.put(&$0, "progressToken", string: token) }
            }
        }
        return writer.finish()
    }
}
