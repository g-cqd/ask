import AemiTesting
import AskAI
import AskAgentCore
import Darwin
import Foundation
import Testing

@testable import AskTools

/// `bash` under the real `sandbox-exec`: every attack the probes found, each against the policy that must stop it,
/// and each beside the ordinary work that must still succeed.
@Suite("Commands run under the sandbox: protected paths hold, ordinary work does not notice", .timeLimit(.minutes(2)))
struct BashSandboxTests {
    private let world: SandboxWorld

    init() throws { world = try SandboxWorld() }

    private func run(_ command: String, policy: SandboxPolicy? = nil) async -> ToolOutput {
        let context = ToolContext(workingDirectory: world.workspace, sandbox: policy ?? world.policy)
        let quoted = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return await BashTool().run(world.input(#"{"command":"\#(quoted)","shell":"/bin/bash"}"#), in: context)
    }

    @Test func `ordinary work succeeds and the output carries no sandbox note`() async {
        let output = await run("echo ok > made.txt && cat made.txt && git init -q . && echo repo")
        #expect(output == ToolOutput("ok\nrepo\n[exit 0]"))
    }

    @Test func `writing ask's configuration fails, however the path is spelled, and the file is untouched`() async {
        for path in [
            world.config + "/config.json", world.home + "/.CONFIG/ASK/config.json", "../.config/ask/config.json"
        ] {
            let output = await run("echo tampered > '\(path)'")
            #expect(output.isError && output.content.contains("Operation not permitted"), "\(path)")
        }
        #expect(world.text(".config/ask/config.json") == "{maxTurns: 5}")
    }

    @Test func `a refused command carries the system's own error and nothing of the policy`() async {
        let output = await run("echo x > '\(world.config)/config.json'")
        #expect(output.isError && output.content.contains("Operation not permitted"))
        for leak in ["sandbox", "Sandbox", "protected", "Only the user", ".aws", "credentials"] {
            #expect(!output.content.replacingOccurrences(of: world.config, with: "").contains(leak), "\(leak)")
        }
    }

    @Test func `credentials, other secret stores and ssh private keys cannot be read, ssh config can`() async {
        #expect((await run("cat '\(world.config)/credentials.json'")).isError)
        #expect((await run("cat '\(world.home)/.aws/credentials'")).isError)
        #expect((await run("cat '\(world.home)/.ssh/id_ed25519'")).isError)
        #expect(await run("cat '\(world.home)/.ssh/config'") == ToolOutput("Host *\n[exit 0]"))
    }

    @Test func `renaming a protected directory's parent away to edit it and back is refused, so the config survives`()
        async
    {
        let attack =
            "mv '\(world.home)/.config' '\(world.home)/.config-away' && echo tampered > '\(world.home)/.config-away/ask/config.json' && mv '\(world.home)/.config-away' '\(world.home)/.config'"
        let output = await run(attack)
        #expect(output.isError)
        #expect(world.text(".config/ask/config.json") == "{maxTurns: 5}")
        #expect(!FileManager.default.fileExists(atPath: world.home + "/.config-away"))
    }

    @Test func `moving a secret directory away to read it under another name is refused`() async {
        let output = await run("mv '\(world.home)/.aws' '\(world.home)/moved' && cat '\(world.home)/moved/credentials'")
        #expect(output.isError && !output.content.contains("aws-secret"))
        #expect(FileManager.default.fileExists(atPath: world.home + "/.aws/credentials"))
    }

    @Test func `a link, a hard link, a rename in and a delete cannot reach into the protected directory`() async {
        let c = world.config
        #expect((await run("ln -s '\(c)/config.json' via && echo x > via")).isError)
        #expect((await run("echo x > f && ln f '\(c)/hard'")).isError)
        #expect((await run("echo x > g && mv g '\(c)/moved'")).isError)
        #expect((await run("rm '\(c)/config.json'")).isError)
        #expect((await run("chmod 777 '\(c)/config.json'")).isError)
        #expect(world.text(".config/ask/config.json") == "{maxTurns: 5}")
        #expect(
            !FileManager.default.fileExists(atPath: c + "/hard")
                && !FileManager.default.fileExists(atPath: c + "/moved"))
    }

    @Test func `ask trust cannot widen the trust store from inside a command, even with a terminal`() async {
        let output = await run("script -q /dev/null /bin/sh -c \"echo '{}' > '\(world.config)/trusted.json'\"")
        #expect(!FileManager.default.fileExists(atPath: world.config + "/trusted.json"), "\(output.content)")
    }

    @Test func `a write scope confines writes, and a protected path inside it stays protected`() async throws {
        let scoped = SandboxPolicy(write: .roots([world.workspace, world.home + "/.config"]))
            .intersecting(world.policy)
        #expect(await run("echo in > inside.txt && cat inside.txt", policy: scoped) == ToolOutput("in\n[exit 0]"))
        // Not under the temporary directory: scratch space is allowed on purpose, and the test home lives there.
        let away = "/Users/Shared/ask-sandbox-test-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: away, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: away) }
        let outside = await run("echo out > '\(away)/out.txt'", policy: scoped)
        #expect(outside.isError && !FileManager.default.fileExists(atPath: away + "/out.txt"))
        let inside = await run("echo t > '\(world.config)/config.json'", policy: scoped)
        #expect(inside.isError && world.text(".config/ask/config.json") == "{maxTurns: 5}")
        #expect(
            await run("d=$(mktemp -d) && echo x > $d/f && echo scratch", policy: scoped)
                == ToolOutput("scratch\n[exit 0]"))
    }

    @Test(arguments: [(SandboxPolicy.Network.any, true, true), (.localhost, true, false), (.none, false, false)])
    func `the network follows the policy`(network: SandboxPolicy.Network, local: Bool, remote: Bool) async throws {
        let listener = socket(AF_INET, SOCK_STREAM, 0)
        defer { close(listener) }
        var address = PortWait.loopback(0)
        let port: Int = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { raw -> Int in
                var length = socklen_t(MemoryLayout<sockaddr_in>.size)
                guard bind(listener, raw, length) == 0, listen(listener, 4) == 0,
                    getsockname(listener, raw, &length) == 0
                else { return 0 }
                return Int(UInt16(bigEndian: pointer.pointee.sin_port))
            }
        }
        let policy = SandboxPolicy(network: network)
        func reaches(_ host: String, _ port: Int) async -> Bool {
            let program = "import socket; socket.create_connection(('\(host)', \(port)), timeout=3)"
            return !(await run("python3 -c \"\(program)\"", policy: policy)).isError
        }
        #expect(port > 0)
        #expect(await reaches("127.0.0.1", port) == local)
        // Whether the machine is online is not the test's business, so "remote allowed" asserts nothing; "remote
        // refused" must hold whether or not the machine is online.
        let outbound = await reaches("1.1.1.1", 53)
        #expect(remote || !outbound, "the network policy let a connection out that it should refuse")
    }

    @Test func `a sandboxed command is still stopped with its children at the timeout`() async throws {
        let clock = TestClock()
        let started = Started()
        let tool = BashTool(clock: clock) { event in
            if case .output(let bytes) = event { started.received(bytes) }
        }
        let context = ToolContext(workingDirectory: world.workspace, sandbox: world.policy)
        async let output = tool.run(
            world.input(#"{"command":"sleep 300 & echo \"child $!\"; wait","timeout_seconds":5,"shell":"/bin/bash"}"#),
            in: context)
        let child = try await started.child()
        try await clock.waitForSleepers(count: 1)
        clock.advance(by: .seconds(5))
        #expect(await output.content.contains("timed out after 5 s"))
        #expect(try await ProcessExit.observed(child), "the child must die with the group even under sandbox-exec")
    }
}
