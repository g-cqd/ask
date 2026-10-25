import AskAI
import AskAgentCore
import Foundation
import Testing

@testable import AskTools

/// What a command the model runs inherits of ask's environment: the table's, less what the policy withholds (ADR-0106).
@Suite("A command is given ask's environment less what the policy withholds, and nothing it did not have")
struct CommandEnvironmentJobTests {
    private static let environment = [
        "PATH": "/usr/bin:/bin", "SECRET_X": "top-secret", "KEEP_Y": "kept", "ANTHROPIC_API_KEY": "key",
        "AWS_PROFILE": "p"
    ]
    private let root = FileManager.default.temporaryDirectory.appending(path: "ask-env-\(UUID().uuidString)")

    private func run(
        _ text: String, policy: CommandEnvironment, table: [String: String] = environment,
        sandbox: SandboxPolicy = .unrestricted
    ) async throws -> String {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let context = ToolContext(workingDirectory: root.path, sandbox: sandbox, commandEnvironment: policy)
        let object = try JSONObject(validating: Array(#"{"command":"\#(text)"}"#.utf8))
        return await BashTool(jobs: JobTable(environment: table)).run(object, in: context).content
    }

    private let probe = #"echo \"[${SECRET_X}][${KEEP_Y}][${ANTHROPIC_API_KEY}][${AWS_PROFILE}]\""#

    @Test func `with no policy a command is given every variable the table holds`() async throws {
        #expect(try await run(probe, policy: .inherit) == "[top-secret][kept][key][p]\n[exit 0]")
    }

    @Test func `a withheld variable is empty to the command and the others are given`() async throws {
        let output = try await run(
            probe, policy: CommandEnvironment(withheld: ["SECRET_X"], withheldPrefixes: ["ANTHROPIC_"]))
        #expect(output == "[][kept][][p]\n[exit 0]")
    }

    @Test func `a prefix withholds, and a pass lets one name through`() async throws {
        let policy = CommandEnvironment(withheldPrefixes: ["AWS_", "ANTHROPIC_"], passed: ["AWS_PROFILE"])
        #expect(try await run(probe, policy: policy) == "[top-secret][kept][][p]\n[exit 0]")
    }

    @Test func `a command is given the table and not the environment of the process that runs the tests`() async throws
    {
        // HOME is set for this process and absent from the table, so a command that sees it was handed more than the table.
        #expect(!(ProcessInfo.processInfo.environment["HOME"] ?? "").isEmpty)
        #expect(try await run(#"echo \"[${HOME}]\""#, policy: .inherit) == "[]\n[exit 0]")
    }

    @Test func `the same holds when the command runs in the sandbox`() async throws {
        let policy = CommandEnvironment(withheld: ["SECRET_X"])
        let output = try await run(probe, policy: policy, sandbox: SandboxPolicy(network: .none))
        #expect(output == "[][kept][key][p]\n[exit 0]")
    }

    @Test func `a name that is not a valid variable name is not given, and the rest are`() async throws {
        let table = Self.environment.merging(["BAD=NAME": "x", "": "y"]) { $1 }
        #expect(try await run(probe, policy: .inherit, table: table) == "[top-secret][kept][key][p]\n[exit 0]")
    }
}
