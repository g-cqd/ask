import Testing

@testable import AskAgentCore

@Suite("The variables an MCP server's settings name are variables ask reads, so a command must not inherit them either")
struct MCPServerVariablesTests {
    @Test
    func `a value names a variable as ${NAME}, alone or inside a longer value, in the environment and the headers`() {
        let server = MCPServerSetting(
            name: "s", env: ["TOKEN": "${GH_TOKEN}", "MIX": "a-${A}-b-${B}"],
            headers: ["authorization": "Bearer ${API_KEY}"])
        #expect(server.referencedVariables == ["GH_TOKEN", "A", "B", "API_KEY"])
    }

    @Test func `a dollar without braces, an unterminated or empty reference and a literal are not variables`() {
        let server = MCPServerSetting(
            name: "s", env: ["A": "$HOME", "B": "${UNTERMINATED", "C": "${}", "D": "plain", "E": "$$"], headers: [:])
        #expect(server.referencedVariables.isEmpty)
    }

    @Test func `a server that names none names none, and a URL server's headers count`() {
        #expect(MCPServerSetting(name: "s", command: "x").referencedVariables.isEmpty)
        #expect(MCPServerSetting(name: "s", url: "https://h", headers: ["x": "${T}"]).referencedVariables == ["T"])
    }

    @Test func `arguments are not scanned: the host does not expand them`() {
        #expect(MCPServerSetting(name: "s", command: "x", args: ["--token", "${NOPE}"]).referencedVariables.isEmpty)
    }
}
