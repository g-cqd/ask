import AskAI
import Testing

@testable import AskAgentCore

/// The tool contract: dispatch by name, arguments decoded per tool, every outcome an output the model can act
/// on, and no output larger than the cap.
@Suite("Tools dispatch by name, and every outcome is a bounded output")
struct ToolRegistryTests {
    private struct Echo: ArgumentTool {
        struct Arguments: Decodable, Sendable { let text: String }
        let definition = ToolDefinition(
            name: "echo", description: "Echo text.",
            inputSchema: try! JSONObject(validating: Array(#"{"type":"object"}"#.utf8)))

        func run(_ arguments: Arguments, in context: ToolContext) async throws(ToolFailure) -> ToolOutput {
            ToolOutput(arguments.text)
        }
    }

    private let context = ToolContext(workingDirectory: "/tmp")
    private func input(_ json: String) -> JSONObject { try! JSONObject(validating: Array(json.utf8)) }

    @Test func `a known tool runs with its decoded arguments`() async throws {
        let registry = try ToolRegistry([Echo()])
        #expect(registry.definitions.map(\.name) == ["echo"])
        #expect(await registry.run(name: "echo", input: input(#"{"text":"hi"}"#), in: context) == ToolOutput("hi"))
    }

    @Test func `an unknown tool and bad arguments are error outputs, not thrown`() async throws {
        let registry = try ToolRegistry([Echo()])
        let unknown = await registry.run(name: "rm", input: input("{}"), in: context)
        #expect(unknown.isError)
        #expect(unknown.content.contains("rm") && unknown.content.contains("echo"))
        let bad = await registry.run(name: "echo", input: input(#"{"text":7}"#), in: context)
        #expect(bad.isError)
        #expect(bad.content.hasPrefix("Invalid arguments for echo"))
    }

    @Test func `two tools with one name are refused`() {
        #expect(throws: ToolRegistry.DuplicateName(name: "echo")) { _ = try ToolRegistry([Echo(), Echo()]) }
    }

    // MARK: - The cap

    @Test func `output within the cap is untouched`() {
        let text = (1 ... 100).map { "line \($0)" }.joined(separator: "\n")
        #expect(OutputCap(maximumLines: 100, maximumBytes: 10_000).apply(text) == text)
    }

    @Test func `too many lines keeps the head and the tail around a marker`() {
        let text = (1 ... 10).map { "line \($0)" }.joined(separator: "\n")
        let capped = OutputCap(maximumLines: 4, maximumBytes: 10_000).apply(text)
        #expect(capped == "line 1\nline 2\n[… 6 lines omitted …]\nline 9\nline 10")
    }

    @Test func `too many bytes cuts on line boundaries and counts what was omitted`() {
        let text = (1 ... 10).map { _ in String(repeating: "x", count: 99) }.joined(separator: "\n")  // 999 bytes
        let capped = OutputCap(maximumLines: 1_000, maximumBytes: 450).apply(text)
        #expect(capped.utf8.count <= 450 + 64)
        #expect(capped.hasPrefix(String(repeating: "x", count: 99) + "\n"))
        #expect(capped.contains("lines omitted"))
        #expect(capped.hasSuffix(String(repeating: "x", count: 99)))
    }

    @Test func `one huge line is cut on a character boundary, never inside one`() {
        let text = String(repeating: "é", count: 1_000)  // 2,000 bytes on one line
        // An odd half-budget (51 bytes) lands inside a two-byte "é", so the cut must step back to a boundary.
        let capped = OutputCap(maximumLines: 1_000, maximumBytes: 103).apply(text)
        #expect(capped.contains("bytes omitted"))
        #expect(capped.unicodeScalars.allSatisfy { $0 == "é" || $0.isASCII || $0 == "…" })
        #expect(!capped.unicodeScalars.contains("\u{FFFD}"), "a split scalar would decode as a replacement character")
        #expect(capped.hasPrefix("ééé") && capped.hasSuffix("ééé"))
    }

    @Test func `the registry caps every tool's output`() async throws {
        let registry = try ToolRegistry([Echo()], cap: OutputCap(maximumLines: 2, maximumBytes: 10_000))
        let output = await registry.run(name: "echo", input: input(#"{"text":"a\nb\nc\nd"}"#), in: context)
        #expect(output.content == "a\n[… 2 lines omitted …]\nd")
    }
}
