import AemiJSON
import AskAI
import AskAgentCore
import AskCodemode
import Foundation
import Synchronization
import Testing

@testable import AskTools

/// One tool, two languages (ADR-0156): `language` says which a script is written in, JavaScript when it says nothing, and
/// Python is offered only where there is a Python to run it.
@Suite("The codemode tool takes a script in JavaScript or in Python", .timeLimit(.minutes(1)))
struct CodemodeLanguageTests {
    /// Which language's child was started, in order.
    private final class Started: Sendable {
        private let languages = Mutex<[String]>([])
        func note(_ language: String) { languages.withLock { $0.append(language) } }
        var all: [String] { languages.withLock { $0 } }
    }

    private let started = Started()

    /// A tool whose JavaScript child is the host in this process; with `python`, its Python child is the same host, so that
    /// which was chosen is seen without a Python.
    private func tool(python: Bool) -> CodemodeTool {
        let started = started
        let javascript: CodemodeChild.Start = { memory in
            started.note("javascript")
            return await CodemodeChildren.inProcess(memory)
        }
        let other: CodemodeChild.Start = { memory in
            started.note("python")
            return await CodemodeChildren.inProcess(memory)
        }
        return CodemodeTool(start: javascript, python: python ? other : nil, scripts: CodemodeLimiter(2))
    }

    private var context: ToolContext {
        let nested = NestedTools(definitions: { [] }, call: { _, _ in ToolOutput("") })
        return ToolContext(workingDirectory: "/work").during(call: "t1").offering(nested)
    }

    private func run(_ arguments: String, python: Bool = true) async -> ToolOutput {
        let input = (try? JSONObject(validating: Array(arguments.utf8))) ?? .empty
        return await tool(python: python).run(input, in: context)
    }

    @Test func `a script that names no language is JavaScript, and one that names one runs on it`() async {
        #expect(await !run(#"{"code":"return 1;"}"#).isError)
        #expect(await !run(#"{"code":"return 1;","language":"javascript"}"#).isError)
        // The stand-in for Python is the JavaScript host: that it was the one started is what is checked.
        #expect(await !run(#"{"code":"return 1;","language":"python"}"#).isError)
        #expect(started.all == ["javascript", "javascript", "python"])
    }

    @Test func `a language ask does not run is refused, and names the two it does`() async {
        let output = await run(#"{"code":"puts 1","language":"ruby"}"#)
        #expect(output.isError && output.content.contains("javascript") && output.content.contains("python"))
        #expect(started.all.isEmpty)
    }

    @Test func `where there is no Python, a Python script is refused with what to do, and nothing starts`() async {
        let output = await run(#"{"code":"return 1","language":"python"}"#, python: false)
        #expect(output.isError)
        #expect(output.content == "There is no python3 on the PATH to run a Python script: write it in JavaScript.")
        #expect(started.all.isEmpty)
    }

    @Test func `the tool describes Python and takes a language only where there is a Python`() {
        let with = tool(python: true).definition
        let schema = String(decoding: with.inputSchema.bytes, as: UTF8.self)
        #expect(with.description.contains("await tools.<name>({...})"))
        #expect(with.description.contains("await tools.name(key=value)") && !with.description.contains("true"))
        #expect(schema.contains(#""language":{"type":"string","enum":["javascript","python"],"description":"#))
        #expect(schema.contains(#""required":["code"]"#), "the language is optional")
        let without = tool(python: false).definition
        #expect(!without.description.contains("Python") && !without.description.contains("python"))
        #expect(!String(decoding: without.inputSchema.bytes, as: UTF8.self).contains("language"))
        #expect(without.name == "codemode" && with.name == "codemode")
    }

    @Test func `a Python script's first line of options is a Python comment`() throws {
        let limits =
            try CodemodeLimits.parse(#"# @options: {"timeout_ms": 30000, "max_output_tokens": 500}"# + "\nreturn 1")
            .get()
        #expect(limits.deadline == .seconds(30) && limits.outputTokens == 500)
        #expect(try CodemodeLimits.parse("# a comment\nreturn 1").get() == CodemodeLimits())
        #expect(
            CodemodeLimits.parse("#@options: {\"timeout_ms\": 0}")
                == .failure(ToolFailure("timeout_ms must be between 1 and 600000."))
        )
    }

    @Test func `a Python script is shown as one, with its length and the tools it names`() throws {
        let code = "a = await tools.read(path=\\\"x\\\")\\nb = await tools[\\\"bash\\\"](command=\\\"ls\\\")\\nreturn a"
        let input = try JSONObject(validating: Array(#"{"language":"python","code":"\#(code)"}"#.utf8))
        #expect(ToolSummary.line(for: input) == "Python script of 3 lines calling read, bash")
        let javascript = try JSONObject(validating: Array(#"{"language":"javascript","code":"return 1;"}"#.utf8))
        #expect(ToolSummary.line(for: javascript) == "script of 1 line")
    }
}
