import AskAgentCore
import Testing

@testable import AskTools

/// A script's own limits, on its first line (ADR-0156, as pi): what it may set, and that anything else is refused out loud.
@Suite("A script sets its deadline and its output on its first line, within what ask allows")
struct CodemodeLimitsTests {
    @Test func `without a first line of options the limits are ask's`() throws {
        let limits = try CodemodeLimits.parse("const a = 1;\nreturn a;").get()
        #expect(limits == CodemodeLimits())
        #expect(limits.deadline == .seconds(120) && limits.outputTokens == 10_000)
        #expect(limits.memoryMiB == 256 && limits.callsInFlight == 16)
    }

    @Test func `the first line may set the deadline and the output, either or both`() throws {
        let both =
            try CodemodeLimits.parse(#"// @options: {"timeout_ms": 30000, "max_output_tokens": 2000}"# + "\nreturn 1;")
            .get()
        #expect(both.deadline == .seconds(30) && both.outputTokens == 2000)
        let one = try CodemodeLimits.parse(#"  //@options:{"max_output_tokens":500}"#).get()
        #expect(one.deadline == .seconds(120) && one.outputTokens == 500)
        #expect(try CodemodeLimits.parse("// @options: {}\nreturn 1;").get() == CodemodeLimits())
    }

    @Test func `options anywhere but the first line are a comment`() throws {
        #expect(try CodemodeLimits.parse("return 1;\n// @options: {\"timeout_ms\": 1}").get() == CodemodeLimits())
        #expect(try CodemodeLimits.parse("// about @options: later").get() == CodemodeLimits())
    }

    @Test(arguments: [
        (#"// @options: {"timeout_ms": 600001}"#, "timeout_ms must be between 1 and 600000."),
        (#"// @options: {"timeout_ms": 0}"#, "timeout_ms must be between 1 and 600000."),
        (#"// @options: {"timeout_ms": "soon"}"#, "timeout_ms must be between 1 and 600000."),
        (#"// @options: {"max_output_tokens": -4}"#, "max_output_tokens must be between 1 and 100000."),
        (#"// @options: {"max_output_tokens": 1.5}"#, "max_output_tokens must be between 1 and 100000."),
        (#"// @options: {"memory_mb": 4096}"#, "memory_mb is not an option: timeout_ms and max_output_tokens are."),
        (#"// @options: {"timeout_ms": 5"#, "The options on the first line are not a JSON object."),
        ("// @options: [1]", "The options on the first line are not a JSON object.")
    ])
    func `what is not one of the two options, or out of range, is refused and says why`(line: String, why: String) {
        #expect(CodemodeLimits.parse(line + "\nreturn 1;") == .failure(ToolFailure(why)))
    }
}
