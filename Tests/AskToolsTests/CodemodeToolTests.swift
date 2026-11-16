import AemiJSON
import AskAI
import AskAgentCore
import AskCodemode
import Foundation
import Synchronization
import Testing

@testable import AskTools

/// The `codemode` tool (ADR-0156): one script that calls the run's other tools and reports what it made of them.
@Suite("The codemode tool runs a script over the run's tools and reports what it said", .timeLimit(.minutes(1)))
struct CodemodeToolTests {
    private let tool = CodemodeTool(start: CodemodeChildren.inProcess, scripts: CodemodeLimiter(2))
    private let calls = Calls()

    /// What the nested tools were called with, in order.
    private final class Calls: Sendable {
        private let made = Mutex<[String]>([])
        func note(_ call: String) { made.withLock { $0.append(call) } }
        var all: [String] { made.withLock { $0 } }
    }

    /// A context whose other tools are `read` (answers with its input) and `fail` (an error), described at length.
    private func context(output directory: String? = nil) -> ToolContext {
        let calls = calls
        let nested = NestedTools(
            definitions: {
                [
                    ToolDefinition(name: "read", description: "Read a file.\nSecond line, with details.") {
                        ToolProperty.string("path")
                    },
                    ToolDefinition(name: "fail", description: String(repeating: "long ", count: 80)) {}
                ]
            },
            call: { name, input in
                let text = String(decoding: input.bytes, as: UTF8.self)
                calls.note("\(name) \(text)")
                return name == "read" ? ToolOutput("read \(text)") : .error("no such file")
            }
        )
        return ToolContext(workingDirectory: "/work", outputDirectory: directory).during(call: "t1").offering(nested)
    }

    private func run(_ code: String, in context: ToolContext? = nil) async -> ToolOutput {
        let input = (try? JSONObject(validating: Array(#"{"code":\#(Self.quoted(code))}"#.utf8))) ?? .empty
        return await tool.run(input, in: context ?? self.context())
    }

    private static func quoted(_ text: String) -> String {
        (try? JSONValue.string(text).encodedBytes()).map { String(decoding: $0, as: UTF8.self) } ?? "\"\""
    }

    /// The report without its first line, whose time is the machine's.
    private func said(_ output: ToolOutput) -> String {
        output.content.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).dropFirst().joined()
    }

    @Test func `a script calls the run's tools with their own arguments, and what it returns is the result`() async {
        let output = await run(#"const a = await tools.read({ path: "note.txt" }); return a.toUpperCase();"#)
        #expect(!output.isError && output.content.hasPrefix("Script completed in "))
        #expect(said(output) == #"READ {"PATH":"NOTE.TXT"}"#)
        #expect(calls.all == [#"read {"path":"note.txt"}"#])
    }

    @Test func `a tool that fails is an Error the script can catch, with the tool's words`() async {
        let output = await run("try { await tools.fail({}); } catch (e) { return 'caught: ' + e.message; }")
        #expect(!output.isError && said(output) == "caught: no such file")
    }

    @Test func `a script that fails is an error result that says why and keeps what it had said`() async {
        let output = await run("text('before');\nawait tools.fail({});")
        #expect(output.isError)
        #expect(output.content.hasPrefix("Script failed after "))
        #expect(output.content.hasSuffix(" s: Error: no such file\nbefore"))
    }

    @Test func `the tools it may call are listed in it by name, each with the first line of what it is for`() async {
        let output = await run("return ALL_TOOLS;")
        let long = String(repeating: "long ", count: 80)
        let expected =
            #"[{"name":"read","description":"Read a file."},{"name":"fail","description":"\#(long.prefix(199))…"}]"#
        #expect(said(output) == expected)
    }

    @Test func `arguments that are not an object are refused before the tool is asked`() async {
        let output = await run("try { await tools.read('note.txt'); } catch (e) { return e.message; }")
        #expect(said(output) == "The arguments of read must be an object, as for a direct call.")
        #expect(calls.all.isEmpty)
    }

    @Test func `options that are refused fail before anything runs`() async {
        let output = await run(#"// @options: {"timeout_ms": 0}"# + "\nawait tools.read({});")
        #expect(output.isError && output.content == "timeout_ms must be between 1 and 600000.")
        #expect(calls.all.isEmpty)
    }

    @Test func `a result past the tokens asked for keeps its ends, and the whole is in a file`() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "ask-codemode-\(UUID().uuidString)").path
        defer { try? FileManager.default.removeItem(atPath: directory) }
        let code =
            #"// @options: {"max_output_tokens": 60}"#
            + "\nfor (let i = 1; i <= 300; i++) console.log('line ' + i); return 'end';"
        let output = await run(code, in: context(output: directory))
        #expect(output.content.contains("lines omitted"))
        let file = directory + "/codemode-t1.txt"
        #expect(output.content.hasSuffix("</console_output>\n[The whole output is in \(file).]"))
        let whole = try String(contentsOfFile: file, encoding: .utf8)
        #expect(whole.contains("line 150\n") && whole.hasSuffix("line 300\n</console_output>"))
    }

    /// The registry cuts a tool's output at 50 KiB and 2,000 lines; a script's is cut here, to what its first line asked for.
    @Test func `what a script returns is bounded here, to its own limit, and says so`() async {
        let code =
            #"// @options: {"max_output_tokens": 50000}"#
            + "\nfor (let i = 0; i < 3000; i++) text('x'.repeat(40)); return 'end';"
        let output = await run(code)
        #expect(output.bounded && !output.content.contains("omitted") && output.content.utf8.count > 120_000)
        let cut = await run(#"// @options: {"max_output_tokens": 60}"# + "\nreturn 'x'.repeat(4000);")
        #expect(cut.bounded && cut.content.contains("omitted"))
    }

    @Test func `outside a turn there is nothing to call, and it says so`() async {
        let output = await run("return 1;", in: ToolContext(workingDirectory: "/work"))
        #expect(
            output.isError
                && output.content == "codemode runs inside a turn of the conversation, where there are tools to call."
        )
    }

    @Test func `it is told how far the script's calls have got`() async throws {
        let lines = Mutex<[String]>([])
        let reporting = ToolContext(
            workingDirectory: "/work",
            progress: { _, line in lines.withLock { $0.append(line) } }
        )
        .during(call: "t1")
        let nested = try #require(context().nested)
        let output = await run("await tools.read({}); await tools.read({}); return 1;", in: reporting.offering(nested))
        #expect(!output.isError)
        #expect(lines.withLock { $0 }.last == "2 of 2 calls done")
    }

    @Test func `its description says how a script calls tools, and it takes one argument`() {
        let definition = tool.definition
        #expect(definition.name == "codemode")
        #expect(definition.description.contains("await tools.<name>({...})"))
        #expect(String(decoding: definition.inputSchema.bytes, as: UTF8.self).contains(#""required":["code"]"#))
    }
}
