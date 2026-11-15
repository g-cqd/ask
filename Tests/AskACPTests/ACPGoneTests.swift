import AemiJSON
import AskTUI
import System
import Testing

@testable import AskACP

/// A client that has gone: its input ends, and there is nobody to read what a turn would still say or to answer what it asks.
@Suite("When the client has gone, what runs for it is stopped, and writing to it ends nothing", .timeLimit(.minutes(1)))
struct ACPGoneTests {
    private let prompt = #"{"sessionId":"s1","prompt":[{"type":"text","text":"build it"}]}"#

    private func session() async -> (client: ACPExchange, conversation: DirectedConversation) {
        let conversation = DirectedConversation()
        let client = ACPExchange { _ in ACPSession(id: "s1", folder: "/work", conversation: conversation) }
        _ = await client.initialize()
        _ = await client.request("session/new", #"{"cwd":"/work"}"#)
        return (client, conversation)
    }

    @Test func `the turn that runs is stopped when the input ends, and the server then finishes`() async {
        let (client, conversation) = await session()
        Task { _ = await client.request("session/prompt", prompt) }
        #expect(await conversation.next() == .started("build it"))
        client.hangUp()
        #expect(await conversation.next() == .stopped, "nobody is left to read its answer")
        conversation.say(.returnQueuedPrompts, .runEnded)
        _ = await client.end()
    }

    @Test func `an approval it was asked is not waited for either`() async {
        let (client, conversation) = await session()
        Task { _ = await client.request("session/prompt", prompt) }
        _ = await conversation.next()
        conversation.say(.askApproval(id: 3, question: "Run `make`?", kind: .grant))
        #expect(await client.nextRequest()?["method"].string == "session/request_permission")
        client.hangUp()
        let said = [await conversation.next(), await conversation.next()]
        #expect(said.contains(.stopped) && said.contains(.answeredApproval(3, .deny)), "\(said)")
        conversation.say(.returnQueuedPrompts, .runEnded)
        _ = await client.end()
    }

    @Test func `writing to a client that no longer reads is an error, and does not end ask`() async throws {
        let pipe = try FileDescriptor.pipe()
        try pipe.readEnd.close()
        defer { try? pipe.writeEnd.close() }
        let sink = DescriptorSink(pipe.writeEnd)
        // Without it, the write raises SIGPIPE, which ends the process: this test then never reports.
        await #expect(throws: Errno.brokenPipe) { try await sink.write(Array("{}\n".utf8)) }
    }

    @Test func `what is written reaches a client that reads, whole and in order`() async throws {
        let pipe = try FileDescriptor.pipe()
        defer {
            try? pipe.readEnd.close()
            try? pipe.writeEnd.close()
        }
        let sink = DescriptorSink(pipe.writeEnd)
        try await sink.write(Array("one\n".utf8))
        try await sink.write(Array("two\n".utf8))
        var buffer = [UInt8](repeating: 0, count: 64)
        let count = try buffer.withUnsafeMutableBytes { try pipe.readEnd.read(into: $0) }
        #expect(String(decoding: buffer[..<count], as: UTF8.self) == "one\ntwo\n")
    }
}
