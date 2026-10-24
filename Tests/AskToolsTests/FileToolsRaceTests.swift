import AskAI
import AskAgentCore
import Darwin
import Foundation
import Synchronization
import Testing

@testable import AskTools

/// The file tools check a path against the sandbox, then use it. A job the sandbox lets write in the workspace can swap a directory in
/// between for a symbolic link to somewhere the sandbox protects: measured, 2 of 6,000 writes landed in ask's own configuration directory
/// (roadmap 0058, ADR-0085). These tests make the swap happen at that exact moment, so the race is no longer a matter of luck.
@Suite("A directory swapped for a link after the sandbox's check cannot redirect a file tool", .timeLimit(.minutes(2)))
struct FileToolsRaceTests {
    private let world: SandboxWorld
    private var work: String { world.workspace }

    init() throws {
        world = try SandboxWorld()
        try FileManager.default.createDirectory(atPath: world.workspace + "/d", withIntermediateDirectories: true)
    }

    /// Replaces the real directory `d` in the workspace with a link to `target`, as a racing job would.
    private func swapDirectory(for target: String) {
        rename(work + "/d", work + "/d.real")
        symlink(target, work + "/d")
    }

    private func exists(_ path: String) -> Bool { FileManager.default.fileExists(atPath: path) }

    // MARK: - Reading

    @Test func `a read cannot be redirected to a protected file by a swapped directory`() throws {
        try Data("decoy".utf8).write(to: URL(filePath: work + "/d/credentials.json"))
        let url = try FileTools.authorized("d/credentials.json", for: [.read], in: world.context)
        var failure: String?
        var text: String?
        do {
            text = try FileTools.text(at: url, shownAs: "d/credentials.json", in: world.context) {
                swapDirectory(for: world.config)
            }
        } catch { failure = error.output.content }
        #expect(text != "sk-ant-secret", "the file the sandbox protects was read")
        #expect(
            failure?.hasPrefix("Sandbox:") == true,
            "refused as the sandbox refuses, not as an accident: \(failure ?? "read \(text ?? "")")")
    }

    // MARK: - Writing

    @Test func `a write cannot be redirected into a protected directory by a swapped directory`() throws {
        let url = try FileTools.authorized("d/pwn.txt", for: [.write], in: world.context)
        var failure: String?
        do {
            try FileTools.write("pwned", to: url, shownAs: "d/pwn.txt", in: world.context) {
                swapDirectory(for: world.config)
            }
        } catch { failure = error.output.content }
        #expect(!exists(world.config + "/pwn.txt"), "a file was created in ask's configuration directory")
        #expect(failure?.hasPrefix("Sandbox:") == true, "refused as the sandbox refuses: \(failure ?? "no failure")")
    }

    @Test func `a write that creates directories cannot be redirected by a swapped ancestor either`() throws {
        let url = try FileTools.authorized("d/new/deeper/pwn.txt", for: [.write], in: world.context)
        var failed = false
        do {
            try FileTools.write("pwned", to: url, shownAs: "d/new/deeper/pwn.txt", in: world.context) {
                swapDirectory(for: world.config)
            }
        } catch { failed = true }
        #expect(failed)
        #expect(!exists(world.config + "/new"), "directories were created inside ask's configuration directory")
    }

    @Test func `a directory swapped for one that may be read but not written is refused a write`() throws {
        let sessions = world.state + "/sessions"
        let url = try FileTools.authorized("d/pwn.txt", for: [.write], in: world.context)
        #expect(throws: ToolFailure.self) {
            try FileTools.write("pwned", to: url, shownAs: "d/pwn.txt", in: world.context) {
                swapDirectory(for: sessions)
            }
        }
        #expect(!exists(sessions + "/pwn.txt"), "the session history directory is readable and must not be writable")
    }

    @Test func `a directory swapped for one that is allowed holding one protected file still protects that file`()
        throws
    {
        let key = world.home + "/.ssh/id_ed25519"
        let url = try FileTools.authorized("d/id_ed25519", for: [.write], in: world.context)
        #expect(throws: ToolFailure.self) {
            try FileTools.write("pwned", to: url, shownAs: "d/id_ed25519", in: world.context) {
                swapDirectory(for: world.home + "/.ssh")
            }
        }
        #expect(try String(contentsOfFile: key, encoding: .utf8) == "PRIVATE KEY")
    }

    @Test func `a name swapped for a link to a protected file is replaced, and the protected file is left alone`()
        throws
    {
        try Data("mine".utf8).write(to: URL(filePath: work + "/target.txt"))
        let url = try FileTools.authorized("target.txt", for: [.write], in: world.context)
        try? FileTools.write("new", to: url, shownAs: "target.txt", in: world.context) {
            unlink(work + "/target.txt")
            symlink(world.config + "/config.json", work + "/target.txt")
        }
        #expect(
            world.text(".config/ask/config.json") == "{maxTurns: 5}", "the protected file was written through the link")
    }

    // MARK: - What keeps working

    @Test
    func `under a restricted policy a write still creates its directories and replaces a file keeping its permissions`()
        throws
    {
        let existing = work + "/d/keep.txt"
        try Data("old".utf8).write(to: URL(filePath: existing))
        chmod(existing, 0o640)
        try FileTools.write(
            "new", to: try FileTools.authorized("d/keep.txt", for: [.write], in: world.context), shownAs: "d/keep.txt",
            in: world.context)
        #expect(try String(contentsOfFile: existing, encoding: .utf8) == "new")
        var info = stat()
        stat(existing, &info)
        #expect(info.st_mode & 0o7777 == 0o640)
        try FileTools.write(
            "deep", to: try FileTools.authorized("d/a/b/c.txt", for: [.write], in: world.context),
            shownAs: "d/a/b/c.txt", in: world.context)
        #expect(try String(contentsOfFile: work + "/d/a/b/c.txt", encoding: .utf8) == "deep")
        #expect(
            try FileManager.default.contentsOfDirectory(atPath: work + "/d/a/b") == ["c.txt"],
            "no temporary file is left")
    }

    @Test func `a read under a restricted policy still reads, and refuses a binary or an oversized file as before`()
        throws
    {
        try Data("hello".utf8).write(to: URL(filePath: work + "/d/a.txt"))
        try Data([0, 1, 2]).write(to: URL(filePath: work + "/d/b.bin"))
        #expect(
            try FileTools.text(
                at: try FileTools.authorized("d/a.txt", for: [.read], in: world.context), shownAs: "d/a.txt",
                in: world.context) == "hello")
        #expect(throws: ToolFailure.self) {
            _ = try FileTools.text(
                at: try FileTools.authorized("d/b.bin", for: [.read], in: world.context), shownAs: "d/b.bin",
                in: world.context)
        }
        #expect(throws: ToolFailure.self) {
            _ = try FileTools.text(
                at: URL(filePath: work + "/d/missing.txt"), shownAs: "d/missing.txt", in: world.context)
        }
    }

    @Test func `a write over a directory fails, says so, and leaves no temporary file behind`() throws {
        try FileManager.default.createDirectory(atPath: work + "/d/sub", withIntermediateDirectories: true)
        let url = try FileTools.authorized("d/sub", for: [.write], in: world.context)
        #expect(throws: ToolFailure.self) { try FileTools.write("x", to: url, shownAs: "d/sub", in: world.context) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: work + "/d") == ["sub"])
    }

    @Test func `a read of a directory, of a file over the limit, and of one that is not there each say what is wrong`()
        throws
    {
        let big = work + "/d/big.bin"
        FileManager.default.createFile(atPath: big, contents: nil)
        let handle = try FileHandle(forWritingTo: URL(filePath: big))
        try handle.truncate(atOffset: UInt64(FileTools.maximumFileBytes + 1))
        try handle.close()
        func failure(_ path: String) -> String {
            do {
                _ = try FileTools.text(
                    at: try FileTools.authorized(path, for: [.read], in: world.context), shownAs: path,
                    in: world.context)
                return "no failure"
            } catch { return error.output.content }
        }
        #expect(failure("d") == "Cannot read d.")
        #expect(failure("d/big.bin").contains("over the \(FileTools.maximumFileBytes)-byte limit"))
        #expect(failure("d/none.txt") == "No file at d/none.txt.")
    }

    // MARK: - A race without help

    @Test func `a racing job that flips the directory as fast as it can lands nothing in the protected directory`()
        async throws
    {
        let running = Atomic<Bool>(true)
        let racer = Thread {
            while running.load(ordering: .relaxed) {
                rename(work + "/d", work + "/d.real")
                symlink(world.config, work + "/d")
                unlink(work + "/d")
                rename(work + "/d.real", work + "/d")
            }
        }
        racer.start()
        defer { running.store(false, ordering: .relaxed) }
        for _ in 0 ..< 2_000 {
            _ = await WriteTool().run(world.input(#"{"path":"d/pwn.txt","content":"x"}"#), in: world.context)
        }
        #expect(!exists(world.config + "/pwn.txt"))
    }
}
