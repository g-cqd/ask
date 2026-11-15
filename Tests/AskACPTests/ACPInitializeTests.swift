import AemiJSON
import Testing

@testable import AskACP

/// `initialize` (ACP v1, Initialization): the version agreed, what the agent can do, who it is. Nothing else is answered before it.
@Suite("A connection opens with initialize, and nothing else is answered before it", .timeLimit(.minutes(1)))
struct ACPInitializeTests {
    @Test func `initialize is answered with the version, the agent's name and version, and no sign-in`() async {
        let client = ACPExchange(agent: ACPImplementation(name: "ask", title: "Ask", version: "7"))
        let answer = await client.initialize()
        let expected: JSONValue = [
            "jsonrpc": "2.0", "id": 1,
            "result": [
                "protocolVersion": 1, "agentCapabilities": [:],
                "agentInfo": ["name": "ask", "title": "Ask", "version": "7"], "authMethods": []
            ]
        ]
        #expect(JSONValue(answer) == expected)
        #expect(await client.end().isEmpty, "and nothing else is written")
    }

    @Test func `an agent with no title sends none`() async {
        let client = ACPExchange()
        let answer = await client.initialize()
        #expect(JSONValue(answer["result"]["agentInfo"]) == ["name": "ask", "version": "0"])
        _ = await client.end()
    }

    @Test(arguments: [0, 1, 2, 99])
    func `whatever version the client names, the answer is the one ask speaks`(version: Int) async {
        let client = ACPExchange()
        #expect(await client.initialize(version: version)["result"]["protocolVersion"].int == 1)
        _ = await client.end()
    }

    @Test func `a string id comes back as it was sent, and the request is the same however the pipe cut it`() async {
        let line = #"{"jsonrpc":"2.0","id":"a","method":"initialize","params":{"protocolVersion":1}}"# + "\n"
        for pieces in [[line], line.map { String($0) }] {
            let client = ACPExchange()
            client.send(raw: pieces)
            let written = await client.end()
            #expect(written.count == 1, "\(pieces.count) pieces")
            #expect(written.first?["id"].string == "a")
            #expect(written.first?["result"]["protocolVersion"].int == 1)
        }
    }

    @Test(arguments: [nil, "{}", #"{"protocolVersion":"one"}"#, "[1]"])
    func `an initialize without a version is refused as invalid parameters, and opens nothing`(params: String?) async {
        let client = ACPExchange()
        let refused = await client.request("initialize", params)
        #expect(refused["error"]["code"].int == -32602)
        #expect(!refused["result"].exists)
        #expect(await client.request("session/new", "{}")["error"]["code"].int == -32600)
        _ = await client.end()
    }

    @Test func `a request before initialize is an invalid request, and after it an unknown method is not found`() async
    {
        let client = ACPExchange()
        let before = await client.request("session/teleport", "{}")
        #expect(before["error"]["code"].int == -32600)
        #expect(before["error"]["message"].string == "Invalid request: session/teleport before initialize")
        _ = await client.initialize()
        let after = await client.request("session/teleport", "{}")
        #expect(after["error"]["code"].int == -32601)
        #expect(after["error"]["message"].string == "Method not found: session/teleport")
        _ = await client.end()
    }

    @Test func `a notification nobody knows is ignored, before and after`() async {
        let client = ACPExchange()
        let notification = #"{"jsonrpc":"2.0","method":"_example/ping","params":{}}"# + "\n"
        client.send(raw: [notification])
        _ = await client.initialize()
        client.send(raw: [notification])
        #expect(await client.end().isEmpty)
    }
}
