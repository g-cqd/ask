import AemiIO
import AskAI
import Foundation
import System
import Testing

@testable import AskAgentCore

/// A picture the person pasted (roadmap 0224): recorded with their message, kept by hash in the session's image store as a tool's,
/// sent beside the text, back on resume, and said in words when its file is gone.
@Suite("A pasted picture is recorded with the message, kept in the store, sent, and back on resume")
struct PastedImageSessionTests {
    private let directory = FileManager.default.temporaryDirectory.appending(path: "ask-pasted-\(UUID().uuidString)")
    private let picture = ImagePart(
        mediaType: "image/png",
        data: (0 ..< 4_000).map { UInt8(truncatingIfNeeded: $0 &* 7) }
    )

    private var path: FilePath { FilePath(directory.appending(path: "s.jsonl").path) }

    private func recorder() throws -> SessionRecorder {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return SessionRecorder(try SessionFile.create(at: path, durability: .none))
    }

    private func loop(_ provider: ScriptedProvider) throws -> AgentLoop {
        AgentLoop(
            provider: provider,
            tools: try ToolRegistry([]),
            settings: AgentSettings(
                model: "m",
                maximumTokens: 64,
                systemPrompt: [],
                maximumTurns: 4,
                acceptsImages: true
            ),
            context: ToolContext(workingDirectory: directory.path)
        )
    }

    private func pasted(_ payload: SessionPayload) -> (text: String, images: [ImagePart])? {
        guard case .user(let text, let images) = payload else { return nil }
        return (text, images)
    }

    @Test func `the first message's picture is recorded, sent after its text, stored once and back on resume`()
        async throws
    {
        do {
            // Released at the end of this scope, so the session can be opened again as a resume opens it.
            let file = try recorder()
            let provider = ScriptedProvider([.reply("A cat.")])
            try await loop(provider).run("what is this", images: [picture], in: file) { _ in }
            #expect(pasted(file.tree.entries[0].payload)?.images == [picture])
            #expect(
                provider.requests[0].messages == [
                    ModelMessage(role: .user, blocks: [.text("what is this"), .image(picture)])
                ]
            )
        }
        let stored = try FileManager.default.contentsOfDirectory(atPath: directory.appending(path: "images").path)
        #expect(stored == [SessionImageStore.hash(of: picture.data)])
        let reopened = try SessionFile.open(at: path)
        #expect(pasted(reopened.tree.entries[0].payload)?.text == "what is this")
        #expect(pasted(reopened.tree.entries[0].payload)?.images == [picture])
        #expect(reopened.clearPictureNames.contains(SessionImageStore.hash(of: picture.data)))
    }

    @Test func `a queued message's picture is recorded with it`() async throws {
        let file = try recorder()
        let queue = PromptQueue()
        queue.append(QueuedPrompt(id: 1, text: "and this", images: [picture]))
        let recorded = try await queue.recordNext(finished: true, in: file)
        #expect(recorded?.images == [picture])
        #expect(pasted(file.tree.entries[0].payload)?.images == [picture])
    }

    @Test func `a message without pictures is written as before, and a lost picture becomes a line`() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            var file = try SessionFile.create(at: path)
            try file.append(.user("plain"))
            try file.append(.user("with", images: [picture]))
        }
        let log = try String(contentsOfFile: path.string, encoding: .utf8)
        #expect(
            log.contains(#""kind":"user","text":"plain"}"#) || log.contains(#"{"kind":"user","text":"plain"}"#),
            "\(log)"
        )
        try FileManager.default.removeItem(atPath: directory.appending(path: "images").path)
        let reopened = try SessionFile.open(at: path)
        let lost = pasted(reopened.tree.entries[1].payload)
        #expect(
            lost?.images == [] && lost?.text.hasPrefix("with\n[an image pasted here is no longer available") == true,
            "\(String(describing: lost))"
        )
    }
}
