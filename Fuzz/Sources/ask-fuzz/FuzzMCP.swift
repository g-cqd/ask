import AemiJSON

@testable import AskMCP

/// An MCP server's output (`LineSplitter`, `MCPEnvelope`, the tool and resource parsers): bytes from a process or a server the person
/// configured but did not write. Promised: the lines do not depend on how the pipe cut them; a message that is not one is reported as
/// malformed; a tool, a result or a resource that is not well formed is nil or text, never a trap.
let fuzzMCP: @Sendable ([UInt8]) -> Void = { bytes in
    guard let seed = bytes.first else { return }
    let stream = bytes.dropFirst()

    func lines(_ chunks: [[UInt8]]) -> [[UInt8]] {
        var splitter = LineSplitter(maximumLineBytes: 4096)
        return chunks.flatMap { splitter.feed($0) }
    }

    let whole = lines([Array(stream)])
    if whole != lines(pieces(of: stream, seed: seed)) { broken("MCP: the lines depend on where the pipe cut them") }
    for line in whole {
        _ = MCPEnvelope.parse(line)
        guard let document = try? AemiJSON.parse(line, options: JSONParseOptions(recordsContainerSpans: true)) else {
            continue
        }
        let root = document.root
        _ = MCPToolParsing.tool(root)
        _ = MCPToolParsing.result(root)
        _ = MCPResourceParsing.resource(root)
        _ = MCPResourceParsing.template(root)
        _ = MCPResourceParsing.contents(root)
    }
}
