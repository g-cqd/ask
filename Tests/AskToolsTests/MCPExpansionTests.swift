import Testing

@testable import AskTools

/// `${NAME}` in a server's settings (ADR-0099): filled from ask's environment, and an unset one is an error, not an empty string, because
/// a server started with `Bearer ` and no token fails in ways that are hard to see.
@Suite("Variables in a server's settings are filled in, and a missing one is named")
struct MCPExpansionTests {
    private func expand(_ value: String, _ environment: [String: String] = ["A": "1", "B": "two", "EMPTY": ""]) throws
        -> String
    {
        try MCPExpansion.expand(["k": value], from: environment)["k"] ?? ""
    }

    @Test func `text without a variable is left alone, dollar signs included`() throws {
        #expect(try expand("plain $A and $") == "plain $A and $")
        #expect(try expand("") == "")
    }

    @Test func `each variable is replaced, wherever it is in the text`() throws {
        #expect(try expand("Bearer ${B}") == "Bearer two")
        #expect(try expand("${A}${B}") == "1two")
        #expect(try expand("x=${A};y=${A}") == "x=1;y=1")
    }

    @Test func `a variable that is set and empty is empty, not missing`() throws {
        #expect(try expand("[${EMPTY}]") == "[]")
    }

    @Test func `an unset variable is named`() {
        #expect(throws: MCPExpansion.Missing(name: "NOPE")) { try expand("a ${NOPE} b") }
    }

    @Test func `an opening that never closes is text, not a variable`() throws {
        #expect(try expand("cost ${A") == "cost ${A")
    }

    @Test func `what a value is replaced with is not looked at again`() throws {
        #expect(try expand("${A}", ["A": "${B}", "B": "no"]) == "${B}")
    }
}
