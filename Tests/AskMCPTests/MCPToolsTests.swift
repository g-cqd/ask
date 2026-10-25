internal import AemiJSON
internal import AskAI
internal import Foundation
internal import Testing

@testable import AskMCP

/// Listing a server's tools and calling one, with what two real servers sent (diary 2026-10-25 (06)): `title`, `annotations` and `outputSchema`
/// beside the usual fields, schemas with `$schema` and `$ref`, results as arrays of typed blocks, a tool's own failure in the result with
/// `isError` and an unknown tool as a protocol error.
@Suite("Tools are listed with their schemas intact and called with their results kept", .timeLimit(.minutes(1)))
struct MCPToolsTests {
    private static let init_ =
        #"{"protocolVersion":"2025-11-25","capabilities":{"tools":{}},"serverInfo":{"name":"s","version":"1"}}"#

    private func started() async throws -> (MCPConnection, ScriptedTransport) {
        let transport = ScriptedTransport()
        transport.on("initialize") { [$0.result(Self.init_)] }
        let connection = MCPConnection(transport: transport, clientName: "ask", clientVersion: "1")
        _ = try await connection.start()
        return (connection, transport)
    }

    // MARK: - Listing

    @Test func `a tool's fields are kept, and its schema is carried byte for byte`() async throws {
        let (connection, transport) = try await started()
        let schema =
            ##"{"$schema":"http://json-schema.org/draft-07/schema#","type":"object","properties":{"n":{"$ref":"#/$defs/n"}},"$defs":{"n":{"type":"integer","minimum":1}}}"##
        transport.on("tools/list") {
            [
                $0.result(
                    ##"{"tools":[{"name":"get-sum","title":"Sum","description":"Adds.","inputSchema":\##(schema),"annotations":{"readOnlyHint":true,"destructiveHint":false,"idempotentHint":true,"openWorldHint":false},"outputSchema":{"type":"object"}}]}"##
                )
            ]
        }
        let tool = try #require(try await connection.listTools().first)
        #expect(tool.name == "get-sum" && tool.title == "Sum" && tool.description == "Adds.")
        #expect(tool.inputSchema.bytes == Array(schema.utf8), "never parsed and written again")
        #expect(tool.hasOutputSchema)
        #expect(
            tool.annotations
                == MCPToolAnnotations(readOnly: true, destructive: false, idempotent: true, openWorld: false))
    }

    @Test func `a tool with nothing but a name is still a tool, with an empty object schema`() async throws {
        let (connection, transport) = try await started()
        transport.on("tools/list") { [$0.result(#"{"tools":[{"name":"bare"}]}"#)] }
        let tool = try #require(try await connection.listTools().first)
        #expect(tool.description == "" && tool.title == nil && tool.annotations == MCPToolAnnotations())
        #expect(tool.inputSchema.bytes == Array(#"{"type":"object"}"#.utf8) && !tool.hasOutputSchema)
    }

    @Test func `a tool that is not an object, or has no name, is skipped and the rest are kept`() async throws {
        let (connection, transport) = try await started()
        transport.on("tools/list") {
            [$0.result(#"{"tools":[1,{"description":"nameless"},{"name":""},{"name":"good"}]}"#)]
        }
        #expect(try await connection.listTools().map(\.name) == ["good"])
    }

    @Test func `pages are followed by their cursor until there is none`() async throws {
        let (connection, transport) = try await started()
        transport.on("tools/list") { sent in
            let root = (try? AemiJSON.parse(Array((sent.params ?? "{}").utf8)).root)
            switch root?["cursor"].string {
                case nil: return [sent.result(#"{"tools":[{"name":"a"}],"nextCursor":"c1"}"#)]
                case "c1": return [sent.result(#"{"tools":[{"name":"b"}],"nextCursor":"c2"}"#)]
                default: return [sent.result(#"{"tools":[{"name":"c"}]}"#)]
            }
        }
        #expect(try await connection.listTools().map(\.name) == ["a", "b", "c"])
        #expect(transport.sent("tools/list").count == 3)
    }

    @Test func `a server whose pages never end is stopped, not followed for ever`() async throws {
        let (connection, transport) = try await started()
        transport.on("tools/list") { [$0.result(#"{"tools":[{"name":"x"}],"nextCursor":"again"}"#)] }
        await #expect(throws: MCPError.tooManyPages) { _ = try await connection.listTools() }
        #expect(transport.sent("tools/list").count == MCPConnection.maximumListPages)
    }

    @Test func `a server that has no tools lists none`() async throws {
        let (connection, transport) = try await started()
        transport.on("tools/list") { [$0.result(#"{"tools":[]}"#)] }
        #expect(try await connection.listTools().isEmpty)
    }

    // MARK: - Calling

    @Test func `a call sends the name and the arguments exactly as given, and returns the blocks in order`()
        async throws
    {
        let (connection, transport) = try await started()
        transport.on("tools/call") {
            [
                $0.result(
                    #"{"content":[{"type":"text","text":"Echo: hi"},{"type":"image","data":"iVBOR","mimeType":"image/png"},{"type":"resource_link","uri":"file:///a","name":"a","mimeType":"text/plain"},{"type":"resource","resource":{"uri":"file:///b","mimeType":"text/plain","text":"inline"}},{"type":"audio","data":"AAAA","mimeType":"audio/wav"},{"type":"hologram"}],"structuredContent":{"x":1}}"#
                )
            ]
        }
        let arguments = try JSONObject(validating: Array(#"{"message":"hi","n":[1,2]}"#.utf8))
        let result = try await connection.callTool("echo", arguments: arguments)
        let params = try #require(transport.sent("tools/call").first?.params)
        let root = try AemiJSON.parse(Array(params.utf8), options: JSONParseOptions(recordsContainerSpans: true)).root
        #expect(root["name"].string == "echo")
        #expect(
            root["arguments"].withRawJSONBytes { String(decoding: $0, as: UTF8.self) } == #"{"message":"hi","n":[1,2]}"#
        )
        #expect(!result.isError)
        #expect(
            result.content == [
                .text("Echo: hi"), .image(mimeType: "image/png", base64: "iVBOR"),
                .resourceLink(uri: "file:///a", name: "a", mimeType: "text/plain"),
                .resource(uri: "file:///b", mimeType: "text/plain", text: "inline"),
                .audio(mimeType: "audio/wav", base64: "AAAA"), .unknown(type: "hologram")
            ])
        #expect(result.structuredContent == Array(#"{"x":1}"#.utf8))
    }

    @Test func `a tool's own failure comes back as a result marked as an error, not as an exception`() async throws {
        let (connection, transport) = try await started()
        transport.on("tools/call") {
            [
                $0.result(
                    #"{"content":[{"type":"text","text":"Input validation error: expected string"}],"isError":true}"#)
            ]
        }
        let result = try await connection.callTool("echo", arguments: .empty)
        #expect(result.isError && result.content == [.text("Input validation error: expected string")])
    }

    @Test func `an unknown tool is the server's protocol error, with its code and words`() async throws {
        let (connection, transport) = try await started()
        transport.on("tools/call") { [$0.failure(-32602, "Tool nope not found")] }
        await #expect(throws: MCPError.rpc(code: -32602, message: "Tool nope not found")) {
            _ = try await connection.callTool("nope", arguments: .empty)
        }
    }

    @Test func `a result that has no content is an empty result, and one that is not an object is malformed`()
        async throws
    {
        let (connection, transport) = try await started()
        transport.on("tools/call") { [$0.result("{}")] }
        let empty = try await connection.callTool("quiet", arguments: .empty)
        #expect(empty.content.isEmpty && !empty.isError)
        transport.on("tools/call") { [$0.result("7")] }
        await #expect(throws: MCPError.self) { _ = try await connection.callTool("odd", arguments: .empty) }
    }

    @Test func `calls made together are answered by id, whatever order the answers come in`() async throws {
        let (connection, transport) = try await started()
        transport.on("tools/call") { sent in
            let name = (try? AemiJSON.parse(Array((sent.params ?? "{}").utf8)).root["name"].string) ?? ""
            return name == "slow" ? [] : [sent.result(#"{"content":[{"type":"text","text":"fast done"}]}"#)]
        }
        async let slow = connection.callTool("slow", arguments: .empty)
        await transport.waitUntilSent("tools/call")
        let fast = try await connection.callTool("fast", arguments: .empty)
        #expect(fast.content == [.text("fast done")])
        let waiting = try #require(transport.sent("tools/call").first)
        transport.push(waiting.result(#"{"content":[{"type":"text","text":"slow done"}]}"#))
        #expect(try await slow.content == [.text("slow done")])
    }
}
