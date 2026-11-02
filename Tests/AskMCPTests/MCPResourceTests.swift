import AemiJSON
import Testing

@testable import AskMCP

/// Roadmap 0067, phase 5: a server's resources. The client lists them and their templates, following pages, and reads one; what a server
/// writes of the wrong shape is skipped, not thrown.
@Suite("A connection lists a server's resources and reads one", .timeLimit(.minutes(1)))
struct MCPResourceTests {
    private func started(resources: Bool = true) async throws -> (MCPConnection, ScriptedTransport, MCPServerInfo) {
        let capabilities = resources ? #"{"tools":{},"resources":{"listChanged":true}}"# : #"{"tools":{}}"#
        let transport = ScriptedTransport()
        transport.on("initialize") {
            [
                $0.result(
                    #"{"protocolVersion":"2025-11-25","capabilities":\#(capabilities),"serverInfo":{"name":"s","version":"1"}}"#
                )
            ]
        }
        let connection = MCPConnection(transport: transport, clientName: "ask", clientVersion: "1")
        let info = try await connection.start()
        return (connection, transport, info)
    }

    @Test func `a server says whether it has resources`() async throws {
        #expect(try await started().2.supportsResources)
        #expect(try await !started(resources: false).2.supportsResources)
    }

    @Test func `the listing follows its pages and skips what is not a resource`() async throws {
        let (connection, transport, _) = try await started()
        transport.on("resources/list") { sent in
            let second = sent.params?.contains(#""cursor":"p2""#) == true
            return [
                second
                    ? sent.result(#"{"resources":[{"uri":"x://b","name":"B"}]}"#)
                    : sent.result(
                        #"{"resources":[{"uri":"x://a","name":"A","title":"The A","description":"first","mimeType":"text/plain"},{"name":"no uri"},7],"nextCursor":"p2"}"#
                    )
            ]
        }
        let listed = try await connection.listResources()
        #expect(
            listed == [
                MCPResource(uri: "x://a", name: "A", title: "The A", description: "first", mimeType: "text/plain"),
                MCPResource(uri: "x://b", name: "B", title: nil, description: nil, mimeType: nil)
            ]
        )
    }

    @Test func `templates are listed with their URI patterns`() async throws {
        let (connection, transport, _) = try await started()
        transport.on("resources/templates/list") {
            [
                $0.result(
                    #"{"resourceTemplates":[{"name":"doc","uriTemplate":"x://doc/{key}","description":"a page"},{"name":"bad"}]}"#
                )
            ]
        }
        #expect(
            try await connection.listResourceTemplates() == [
                MCPResourceTemplate(uriTemplate: "x://doc/{key}", name: "doc", description: "a page", mimeType: nil)
            ]
        )
    }

    @Test func `reading gives each part as text or as base64 bytes, and asks for the URI given`() async throws {
        let (connection, transport, _) = try await started()
        transport.on("resources/read") {
            [
                $0.result(
                    ##"{"contents":[{"uri":"x://a","mimeType":"text/markdown","text":"# A"},{"uri":"x://a.png","mimeType":"image/png","blob":"AAEC"},{"uri":"x://odd"}]}"##
                )
            ]
        }
        let parts = try await connection.readResource("x://a")
        #expect(
            parts == [
                MCPResourceContents(uri: "x://a", mimeType: "text/markdown", body: .text("# A")),
                MCPResourceContents(uri: "x://a.png", mimeType: "image/png", body: .blob(base64: "AAEC"))
            ]
        )
        let params = try #require(transport.sent("resources/read").first?.params)
        #expect(try AemiJSON.parse(Array(params.utf8)).root["uri"].string == "x://a")
    }
}
