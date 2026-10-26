import AskAI
import AskAgentCore
import Foundation
import Testing

@testable import AskTools

/// The file tools under the default policy: what they refuse, how they say so, and that a refusal does nothing.
@Suite("The file tools refuse what the sandbox protects, and say which capability and path")
struct FileToolsSandboxTests {
    private let world: SandboxWorld

    init() throws { world = try SandboxWorld() }

    private func read(_ path: String) async -> ToolOutput {
        await ReadTool().run(world.input(#"{"path":"\#(path)"}"#), in: world.context)
    }

    private func write(_ path: String) async -> ToolOutput {
        await WriteTool().run(world.input(#"{"path":"\#(path)","content":"tampered"}"#), in: world.context)
    }

    private func edit(_ path: String) async -> ToolOutput {
        await EditTool()
            .run(world.input(#"{"path":"\#(path)","old_text":"history","new_text":"tampered"}"#), in: world.context)
    }

    @Test func `reading ask's credentials is refused with the path the model gave and nothing of the policy`() async {
        let output = await read(world.config + "/credentials.json")
        #expect(output == .error("Not permitted: " + world.config + "/credentials.json."))
        #expect(!output.content.contains("sk-ant-secret"))
    }

    @Test func `writing or editing ask's configuration is refused, and the file is untouched`() async {
        let target = world.config + "/config.json"
        #expect((await write(target)).content.hasPrefix("Not permitted:"))
        #expect(await edit(target).isError)
        #expect(world.text(".config/ask/config.json") == "{maxTurns: 5}")
    }

    @Test func `editing a file that may not be read says reading is the problem, before anything is read`() async {
        let output = await EditTool()
            .run(
                world.input(#"{"path":"\#(world.config)/credentials.json","old_text":"sk-ant","new_text":"x"}"#),
                in: world.context)
        #expect(output.isError && output.content.hasPrefix("Not permitted:"))
        #expect(!output.content.contains("sk-ant-secret"))
        #expect(world.text(".config/ask/credentials.json") == "sk-ant-secret")
    }

    @Test func `a refused write creates nothing, not even the directories it would have created`() async {
        let output = await write(world.config + "/new/deeper/file.txt")
        #expect(output.isError)
        #expect(!FileManager.default.fileExists(atPath: world.config + "/new"))
    }

    @Test func `the state directory can be read but not written or edited`() async {
        let session = world.state + "/sessions/s.jsonl"
        #expect(await read(session) == ToolOutput("history"))
        #expect((await write(session)).content.hasPrefix("Not permitted:"))
        #expect((await edit(session)).content.hasPrefix("Not permitted:"))
        #expect(world.text(".local/state/ask/sessions/s.jsonl") == "history")
    }

    @Test func `secret stores and ssh private keys are unreadable, ssh's config is not`() async {
        #expect((await read(world.home + "/.aws/credentials")).isError)
        #expect((await read(world.home + "/.ssh/id_ed25519")).isError)
        #expect(await read(world.home + "/.ssh/config") == ToolOutput("Host *"))
    }

    @Test func `a link in the workspace does not lead past the policy, nor does a dangling one, nor dot-dot`()
        async throws
    {
        let work = world.workspace
        try FileManager.default.createSymbolicLink(atPath: work + "/cfg", withDestinationPath: world.config)
        try FileManager.default.createSymbolicLink(
            atPath: work + "/dangling", withDestinationPath: world.config + "/planted.json")
        #expect((await read("cfg/credentials.json")).isError)
        #expect((await write("cfg/config.json")).isError)
        #expect((await write("dangling")).isError)
        #expect((await write("../.config/ask/planted.json")).isError)
        #expect((await write("../.CONFIG/ASK/planted.json")).isError)
        #expect(!FileManager.default.fileExists(atPath: world.config + "/planted.json"))
        #expect(world.text(".config/ask/config.json") == "{maxTurns: 5}")
    }

    @Test func `ordinary work in the workspace is unaffected`() async {
        #expect(await read("file.txt") == ToolOutput("workspace file"))
        #expect(!(await write("sub/new.txt")).isError)
        #expect(world.text("work/sub/new.txt") == "tampered")
        #expect(
            !(await EditTool()
                .run(world.input(#"{"path":"file.txt","old_text":"workspace","new_text":"edited"}"#), in: world.context))
                .isError)
        #expect(world.text("work/file.txt") == "edited file")
    }

    @Test func `the write goes to the path that was checked, so a link in the way is followed once, not trusted again`()
        async throws
    {
        try FileManager.default.createSymbolicLink(
            atPath: world.workspace + "/alias", withDestinationPath: world.home + "/elsewhere")
        #expect(!(await write("alias/out.txt")).isError)
        #expect(world.text("elsewhere/out.txt") == "tampered")
    }

    @Test
    func `what the check approves is returned canonical, so the tool uses that and not the spelling it was given`()
        throws
    {
        try FileManager.default.createSymbolicLink(
            atPath: world.workspace + "/alias", withDestinationPath: world.home + "/elsewhere")
        let url = try FileTools.authorized("alias/./../elsewhere/out.txt", for: [.write], in: world.context)
        #expect(url.path == world.home + "/elsewhere/out.txt")
        let plain = try FileTools.authorized("file.txt", for: [.read], in: world.context)
        #expect(plain.path == world.workspace + "/file.txt")
    }

    @Test func `a path that cannot be resolved is refused`() async throws {
        try FileManager.default.createSymbolicLink(
            atPath: world.workspace + "/loop", withDestinationPath: world.workspace + "/loop")
        #expect((await read("loop")).content == "Not permitted: loop.")
    }
}
