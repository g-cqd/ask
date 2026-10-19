import AskAI
import AskAgentCore
import Foundation
import Testing

@testable import AskTools

/// The whole output of a command goes to a file, kept only when the result had to be cut, and named in it.
@Suite("A result cut to fit names a file holding the whole output")
struct JobOutputFileTests {
    private let root = FileManager.default.temporaryDirectory.appending(path: "ask-joboutput-\(UUID().uuidString)")

    private func run(_ command: String) async throws -> (ToolOutput, [String]) {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let outputs = root.appending(path: "output").path
        let context = ToolContext(workingDirectory: root.path, outputDirectory: outputs)
        let json = #"{"command":"\#(command.replacingOccurrences(of: "\\", with: "\\\\"))"}"#
        let output = await BashTool().run(try JSONObject(validating: Array(json.utf8)), in: context)
        let files = (try? FileManager.default.contentsOfDirectory(atPath: outputs)) ?? []
        return (output, files.map { outputs + "/" + $0 })
    }

    @Test func `a short result leaves no file behind`() async throws {
        let (output, files) = try await run("echo short")
        #expect(output == ToolOutput("short\n[exit 0]"))
        #expect(files.isEmpty)
    }

    @Test func `a long result keeps the whole output in a file and names it`() async throws {
        let (output, files) = try await run("head -c 3000000 /dev/zero | tr '\\\\0' 'x'; echo; echo END")
        let file = try #require(files.first)
        #expect(files.count == 1)
        #expect(output.content.hasSuffix("[whole output in \(file)]\n[exit 0]"))
        let saved = try Data(contentsOf: URL(filePath: file))
        #expect(saved.count == 3_000_005)
        #expect(saved.suffix(4) == Data("END\n".utf8))
        let mode = try FileManager.default.attributesOfItem(atPath: file)[.posixPermissions] as? Int
        #expect(mode == 0o600)
    }
}
