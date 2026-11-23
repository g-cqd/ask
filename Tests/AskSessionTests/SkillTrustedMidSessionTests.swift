internal import AskAI
internal import AskAgentCore
internal import AskTUI
internal import AskTools
internal import Foundation
internal import Synchronization
internal import Testing

@testable import AskSession

/// A project skill the person trusts while ask runs (`ask trust --skills` in another terminal) reaches the model at their next
/// message: the `skill` tool loads it, a note names it once, and the list at the session's start is left as it was.
@Suite("A skill trusted mid-session reaches the model")
struct SkillTrustedMidSessionTests {
    @Test func `the first message only looks; a trust later is named once, and the tool serves the skill`() async throws
    {
        let fixture = try await ConversationFixture()
        let conversation = fixture.conversation
        let project = fixture.root.appending(path: "project").path
        let folder = project + "/.agents/skills/deploy-check"
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        let file = folder + "/SKILL.md"
        try Data("---\nname: deploy-check\ndescription: Checks a deploy.\n---\n# Deploy check\n".utf8)
            .write(to: URL(filePath: file))
        let trustPath = conversation.source.loader.trustPath
        let book = {
            SkillBook(
                conversation.current.withLock { $0.settings }.configuration,
                workingDirectory: project,
                trustPath: trustPath
            )
        }
        let before = book()
        conversation.skillTrust.shelf.replace(before.catalog, knownSources: before.knownSources)
        #expect(!before.catalog.skills.contains { $0.name == "deploy-check" }, "not trusted: not loaded")

        #expect(conversation.attachingNewlyTrustedSkills("hello", update: fixture.update) == "hello", "the first look")
        // What `ask trust --skills` records: the file's real path and its digest.
        var trust = ProjectTrust()
        trust.trust(
            URL(filePath: file).resolvingSymlinksInPath().path,
            digest: ProjectTrust.digest(Array(try Data(contentsOf: URL(filePath: file))))
        )
        try FileManager.default.createDirectory(
            atPath: (trustPath as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true
        )
        try trust.save(to: trustPath)

        let sent = conversation.attachingNewlyTrustedSkills("deploy now", update: fixture.update)
        #expect(
            sent.hasPrefix("Skills the user trusted during this session") && sent.contains("deploy-check")
                && sent.hasSuffix("deploy now")
        )
        #expect(
            fixture.updates.contains {
                if case .notice(let text, _) = $0 { text.contains("deploy-check") } else { false }
            }
        )
        #expect(
            conversation.skillTrust.shelf.catalog.skills.contains { $0.name == "deploy-check" },
            "the tool serves it"
        )
        let tool = SkillTool(shelf: conversation.skillTrust.shelf)
        let loaded = await tool.run(
            try JSONObject(validating: Array(#"{"name":"deploy-check"}"#.utf8)),
            in: ToolContext(workingDirectory: project)
        )
        #expect(loaded.content.contains("# Deploy check"))
        #expect(conversation.attachingNewlyTrustedSkills("again", update: fixture.update) == "again", "named once")
    }

    @Test func `a trust store unchanged is a stat, nothing more; a change is seen once`() throws {
        let skills = SessionSkills()
        let path = FileManager.default.temporaryDirectory.appending(path: "ask-trust-stamp-\(UUID().uuidString).json")
            .path
        defer { try? FileManager.default.removeItem(atPath: path) }
        #expect(!skills.trustChanged(at: path), "the first look only remembers")
        #expect(!skills.trustChanged(at: path))
        try Data("{}".utf8).write(to: URL(filePath: path))
        #expect(skills.trustChanged(at: path), "made")
        #expect(!skills.trustChanged(at: path), "seen")
        try Data("{\"a\":1}".utf8).write(to: URL(filePath: path))
        #expect(skills.trustChanged(at: path), "changed")
    }
}
