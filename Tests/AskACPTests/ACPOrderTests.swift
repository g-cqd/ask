import AemiJSON
import Testing

@testable import AskACP

/// What a client writes in one go is read in the order it wrote it, and what cannot be read is answered (JSON-RPC 2.0): the
/// connection serves (AemiJSON's roadmap 0011), where it answered each request in a task of its own and dropped the rest.
@Suite("Requests are taken in the order they arrive, and what cannot be read is answered", .timeLimit(.minutes(1)))
struct ACPOrderTests {
    @Test func `a request written behind initialize is not refused as before it`() async {
        // Fifty times: one task for each request made the order a matter of scheduling.
        for round in 0 ..< 50 {
            let client = ACPExchange { _ in ACPSession(id: "s", folder: "/work", conversation: DirectedConversation()) }
            client.send(raw: [
                #"{"jsonrpc":"2.0","id":80,"method":"initialize","params":{"protocolVersion":1}}"# + "\n"
                    + #"{"jsonrpc":"2.0","id":81,"method":"session/new","params":{"cwd":"/work"}}"# + "\n"
            ])
            #expect(await client.answer(to: 81)["result"]["sessionId"].string == "s", "round \(round)")
            _ = await client.end()
        }
    }

    @Test func `a request written before initialize is refused, whatever follows it`() async {
        for round in 0 ..< 50 {
            let client = ACPExchange { _ in ACPSession(id: "s", folder: "/work", conversation: DirectedConversation()) }
            client.send(raw: [
                #"{"jsonrpc":"2.0","id":81,"method":"session/new","params":{"cwd":"/work"}}"# + "\n"
                    + #"{"jsonrpc":"2.0","id":80,"method":"initialize","params":{"protocolVersion":1}}"# + "\n"
            ])
            #expect(await client.answer(to: 81)["error"]["code"].int == -32600, "round \(round)")
            _ = await client.end()
        }
    }

    @Test func `a line that is not JSON, and one that is not a request, are answered with their errors, in order`()
        async
    {
        let client = ACPExchange()
        client.send(raw: ["this is not JSON\n", #"{"jsonrpc":"1.0","id":"x","method":"initialize"}"# + "\n"])
        #expect(await client.initialize()["result"]["protocolVersion"].int == 1, "and the connection goes on")
        let refused = await client.end()
        #expect(refused.map { $0["error"]["code"].int } == [-32700, -32600])
        #expect(refused.first?["id"].isNull == true && refused.last?["id"].string == "x")
    }
}
