import AskAI
import AskAgentCore
import Foundation
import Testing

@testable import AskTools

/// read, write and edit, each in its own scratch directory.
@Suite("File tools read, write and edit exactly, and refuse what they cannot do safely")
struct FileToolsTests {
    private let root: URL
    private let context: ToolContext

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "ask-tools-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        context = ToolContext(workingDirectory: root.path)
    }

    private func input(_ json: String) -> JSONObject { try! JSONObject(validating: Array(json.utf8)) }
    private func file(_ name: String, _ text: String) throws {
        try Data(text.utf8).write(to: root.appending(path: name))
    }
    private func contents(_ name: String) throws -> String {
        String(decoding: try Data(contentsOf: root.appending(path: name)), as: UTF8.self)
    }

    // MARK: - read

    @Test func `read returns a file's text, relative to the working directory`() async throws {
        try file("a.txt", "one\ntwo\nthree\n")
        #expect(await ReadTool().run(input(#"{"path":"a.txt"}"#), in: context) == ToolOutput("one\ntwo\nthree\n"))
        let absolute = root.appending(path: "a.txt").path
        #expect(await ReadTool().run(input(#"{"path":"\#(absolute)"}"#), in: context).content == "one\ntwo\nthree\n")
    }

    @Test func `read takes a window of lines and says which`() async throws {
        try file("a.txt", "1\n2\n3\n4\n5")
        let output = await ReadTool().run(input(#"{"path":"a.txt","offset":2,"limit":2}"#), in: context)
        #expect(output == ToolOutput("2\n3\n[lines 2–3 of 5]"))
        let past = await ReadTool().run(input(#"{"path":"a.txt","offset":9}"#), in: context)
        #expect(past.isError)
    }

    @Test func `read refuses binary and missing files with a reason`() async throws {
        try Data([0x7F, 0x45, 0x00, 0x01]).write(to: root.appending(path: "bin"))
        let binary = await ReadTool().run(input(#"{"path":"bin"}"#), in: context)
        #expect(binary.isError && binary.content.contains("binary"))
        let missing = await ReadTool().run(input(#"{"path":"nope.txt"}"#), in: context)
        #expect(missing.isError && missing.content.contains("nope.txt"))
    }

    @Test func `read refuses a file over the size limit before reading it`() async throws {
        // Sparse: extended without writing, so the test costs no disk.
        let url = root.appending(path: "huge.log")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(FileTools.maximumFileBytes + 1))
        try handle.close()
        let output = await ReadTool().run(input(#"{"path":"huge.log"}"#), in: context)
        #expect(output.isError && output.content.contains("limit"))
    }

    // MARK: - write (unified write + targeted replacement)

    @Test func `write creates parent directories and replaces whole files with content`() async throws {
        let output = await WriteTool().run(input(#"{"path":"new/dir/b.txt","content":"hello"}"#), in: context)
        #expect(!output.isError)
        #expect(try contents("new/dir/b.txt") == "hello")
        _ = await WriteTool().run(input(#"{"path":"new/dir/b.txt","content":"bye"}"#), in: context)
        #expect(try contents("new/dir/b.txt") == "bye")
    }

    @Test func `new_text alone is an edit that lost its old_text, not the whole file`() async throws {
        try file("whole.txt", "a long file\nwith a line to change\n")
        let lost = await WriteTool().run(input(#"{"path":"whole.txt","new_text":"with a line changed"}"#), in: context)
        #expect(lost.isError && lost.content.contains("old_text") && lost.content.contains("content"))
        #expect(try contents("whole.txt") == "a long file\nwith a line to change\n")
        let nothing = await WriteTool().run(input(#"{"path":"whole.txt"}"#), in: context)
        #expect(nothing.isError && nothing.content.contains("content"))
    }

    @Test func `write executes targeted string replacement when old_text and new_text are provided`() async throws {
        try file("unified.txt", "alpha beta gamma")
        let output = await WriteTool()
            .run(input(#"{"path":"unified.txt","old_text":"beta","new_text":"omega"}"#), in: context)
        #expect(!output.isError)
        #expect(try contents("unified.txt") == "alpha omega gamma")
    }

    @Test func `write with old_text requires new_text and enforces unique occurrence`() async throws {
        try file("dup.txt", "token token token")
        let missing = await WriteTool().run(input(#"{"path":"dup.txt","old_text":"token"}"#), in: context)
        #expect(missing.isError && missing.content.contains("new_text"))
        let multi = await WriteTool()
            .run(input(#"{"path":"dup.txt","old_text":"token","new_text":"one"}"#), in: context)
        #expect(multi.isError && multi.content.contains("3"))
        let replaced = await WriteTool()
            .run(input(#"{"path":"dup.txt","old_text":"token","new_text":"one","replace_all":true}"#), in: context)
        #expect(!replaced.isError)
        #expect(try contents("dup.txt") == "one one one")
    }

    @Test func `write rejects ambiguous modes without touching the file`() async throws {
        try file("mixed.txt", "original")
        for json in [
            #"{"path":"mixed.txt","content":"overwrite","new_text":"other"}"#,
            #"{"path":"mixed.txt","content":"overwrite","old_text":"original","new_text":"edit"}"#
        ] {
            let result = await WriteTool().run(input(json), in: context)
            #expect(result.isError)
            #expect(try contents("mixed.txt") == "original")
        }
    }

    // MARK: - edit

    @Test func `edit replaces the one exact match and keeps permissions`() async throws {
        try file("c.sh", "echo one\necho two\n")
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: root.appending(path: "c.sh").path
        )
        let output = await EditTool()
            .run(input(#"{"path":"c.sh","old_text":"echo two","new_text":"echo 2"}"#), in: context)
        #expect(!output.isError)
        #expect(try contents("c.sh") == "echo one\necho 2\n")
        let mode =
            try FileManager.default.attributesOfItem(atPath: root.appending(path: "c.sh").path)[.posixPermissions]
        #expect(mode as? Int == 0o755)
    }

    /// A script makes its calls at once (ADR-0156). An edit reads, changes and writes back: sixteen at once on one file each
    /// said it was made, and two or three were (diary 2026-11-16-03).
    @Test func `edits made at once to one file are all made`() async throws {
        let count = 64
        let padding = String(repeating: "a line that is only here to make the file long\n", count: 2000)
        try file("many.txt", (0 ..< count).map { "marker-\($0)-old\n" }.joined() + padding)
        let context = context
        let made = await withTaskGroup(of: Bool.self) { group in
            for index in 0 ..< count {
                let input = input(
                    #"{"path":"many.txt","old_text":"marker-\#(index)-old","new_text":"marker-\#(index)-new"}"#
                )
                group.addTask { !(await EditTool().run(input, in: context).isError) }
            }
            return await group.reduce(into: 0) { $0 += $1 ? 1 : 0 }
        }
        #expect(made == count)
        #expect(try contents("many.txt") == (0 ..< count).map { "marker-\($0)-new\n" }.joined() + padding)
    }

    @Test func `edit refuses no match and several matches, and changes nothing`() async throws {
        try file("d.txt", "x x x")
        let none = await EditTool().run(input(#"{"path":"d.txt","old_text":"y","new_text":"z"}"#), in: context)
        #expect(none.isError && none.content.contains("not found"))
        let many = await EditTool().run(input(#"{"path":"d.txt","old_text":"x","new_text":"z"}"#), in: context)
        #expect(many.isError && many.content.contains("3"))
        #expect(try contents("d.txt") == "x x x")
        let all = await EditTool()
            .run(input(#"{"path":"d.txt","old_text":"x","new_text":"z","replace_all":true}"#), in: context)
        #expect(!all.isError)
        #expect(try contents("d.txt") == "z z z")
        #expect(all.facts.replacements == 3, "the count is a typed fact for the header (roadmap 0078)")
        #expect(none.facts.replacements == nil && many.facts.replacements == nil, "a refused edit replaced nothing")
    }

    @Test func `edit matches exact bytes, not canonically equivalent text`() async throws {
        try file("e.txt", "caf\u{0065}\u{0301} and café")  // decomposed, then precomposed
        let output = await EditTool().run(input(#"{"path":"e.txt","old_text":"café","new_text":"tea"}"#), in: context)
        #expect(!output.isError, "only the precomposed form matches the quoted bytes")
        #expect(try contents("e.txt") == "caf\u{0065}\u{0301} and tea")
    }

    @Test func `the tools register together under distinct names`() throws {
        let registry = try ToolRegistry(FileTools.all)
        #expect(registry.definitions.map(\.name) == ["read", "write"])
    }
}
