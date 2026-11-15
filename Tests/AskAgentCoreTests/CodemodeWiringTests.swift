import AskAI
import Testing

@testable import AskAgentCore

/// What the rest of ask knows of the `codemode` tool (ADR-0156): that a script is asked about once, how its call is shown, and
/// the setting that turns it off.
@Suite("A codemode script is asked about as a whole, shown as its lines, and can be turned off")
struct CodemodeWiringTests {
    private func input(_ code: String) -> JSONObject {
        let quoted = code.replacing("\\", with: "\\\\").replacing("\"", with: "\\\"").replacing("\n", with: "\\n")
        return try! JSONObject(validating: Array(#"{"code":"\#(quoted)"}"#.utf8))
    }

    private let script =
        "const a = await tools.read({ path: 'x' });\nawait tools.bash({ command: 'make' });\nreturn tools[\"mcp__dev__search\"]({});"

    @Test func `a script asks the person, once, as a tool; an answer for the session covers the next`() {
        let decision = ApprovalPolicy().decide(tool: "codemode", input: input(script), workingDirectory: "/p")
        guard case .ask(let approval) = decision else {
            Issue.record("a script was not asked about: \(decision)")
            return
        }
        #expect(approval.tool == "codemode" && approval.scope == .tool("codemode"))
    }

    @Test func `the lists and the flags cover it as they cover any tool`() {
        let script = input(script)
        #expect(ApprovalPolicy(flag: .yes).decide(tool: "codemode", input: script, workingDirectory: "/p") == .run)
        #expect(
            ApprovalPolicy(allowing: ["codemode"]).decide(tool: "codemode", input: script, workingDirectory: "/p")
                == .run
        )
        let allowing = ApprovalPolicy(section: ApprovalsSection(defaultMode: .allow))
        #expect(allowing.decide(tool: "codemode", input: script, workingDirectory: "/p") == .run)
    }

    @Test func `its call is shown as its length and the tools it names, and whole as the script`() {
        #expect(ToolSummary.line(for: input(script)) == "script of 3 lines calling read, bash, mcp__dev__search")
        #expect(ToolSummary.line(for: input("return 1 + 1;")) == "script of 1 line")
        #expect(
            ToolSummary.line(for: input("await tools.read({}); await tools.read({});\n"))
                == "script of 1 line calling read"
        )
        #expect(ToolSummary.fullInput(for: input(script)) == script)
        #expect(
            ToolSummary.header(for: input(script), tool: "codemode")
                == "script of 3 lines calling read, bash, mcp__dev__search"
        )
    }

    @Test func `codemode is on unless a file turns it off`() throws {
        #expect(Configuration.defaults.codemode.value == true)
        let file = try ConfigurationFile.parse(Array(#"{"codemode": "off"}"#.utf8), path: "c.json")
        #expect(file.codemode == false && file.sets("codemode"))
        let configured = Configuration.defaults.applying(file, from: .file("/u/config.json"))
        #expect(configured.codemode.value == false)
        #expect(configured.changes(from: .defaults) == ["codemode: true → false (/u/config.json)"])
        #expect(try ConfigurationFile.parse(Array(#"{"codemode": true}"#.utf8), path: "c.json").codemode == true)
        #expect(throws: ConfigurationError.self) {
            try ConfigurationFile.parse(Array(#"{"codemode": "only"}"#.utf8), path: "c.json")
        }
        #expect(ConfigurationFile.keys.contains("codemode"))
    }
}
